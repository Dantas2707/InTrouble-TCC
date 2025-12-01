import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class SosMediaRecorder {
  /// Intervalo entre fotos (já vem configurado pelo ADM)
  final Duration photoInterval;

  /// Duração máxima da gravação de áudio (configurada pelo ADM)
  final Duration audioDuration;

  /// Qualidade do JPEG (se quiser usar depois)
  final int jpegQuality;

  SosMediaRecorder({
    this.photoInterval = const Duration(minutes: 1),
    this.audioDuration = const Duration(minutes: 1),
    this.jpegQuality = 85,
  });

  /// Factory para criar o recorder com base nas configurações do ADM
  /// Salvas em: collection('config').doc('sos_media')
  static Future<SosMediaRecorder> fromRemoteConfig() async {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('sos_media')
        .get();

    final data = doc.data() ?? {};

    // Valores em segundos no Firestore; se não tiver nada, usa 60s
    final photoSeconds =
        (data['photoIntervalSeconds'] as num?)?.toInt() ?? 60;
    final audioSeconds =
        (data['audioDurationSeconds'] as num?)?.toInt() ?? 60;
    final jpegQuality =
        (data['jpegQuality'] as num?)?.toInt() ?? 85;

    return SosMediaRecorder(
      photoInterval: Duration(seconds: photoSeconds),
      audioDuration: Duration(seconds: audioSeconds),
      jpegQuality: jpegQuality,
    );
  }

  final _recorder = AudioRecorder();
  CameraController? _camera;
  Timer? _photoTimer;
  Timer? _audioLimitTimer;

  final List<File> _photos = [];
  File? _audioFile;
  bool _started = false;

  // ====== PUBLIC API ======

  Future<void> start({Future<void> Function()? onMaxDurationReached}) async {
    if (_started) return;
    _started = true;

    // 1) Permissões
    await _ensurePermissions();

    // 2) Inicializar câmera (preferir traseira)
    await _initCamera();

    // 3) Agendar fotos periódicas
    await _takePhoto(); // tira uma foto logo no início
    _photoTimer = Timer.periodic(photoInterval, (_) => _takePhoto());

    // 4) Gravar áudio por até audioDuration
    await _recordAudioLimited(onMaxDurationReached: onMaxDurationReached);
  }

  /// Para tudo e faz upload para o Storage, registrando referências no Firestore.
  /// Retorna os caminhos (gs://) enviados.
  Future<void> stopAndUpload({
    required String ocorrenciaId,
    required String ownerUid,
  }) async {
   // Parar timers, câmera e gravação garantindo o arquivo de áudio
    final File? audio = await stop();


    // Upload: sos/{uid}/{ocorrenciaId}/photos/ e /audio/
    final storage = FirebaseStorage.instance;
    final now = DateTime.now().toUtc(); // se quiser usar no nome depois

    final List<String> photoUrls = [];
    for (final f in _photos) {
      final name = f.path.split('/').last;
      final ref = storage
          .ref()
          .child('sos/$ownerUid/$ocorrenciaId/photos/$name');
      await ref.putFile(f);
      final url = await ref.getDownloadURL();
      photoUrls.add(url);

      // Registrar no Firestore no campo 'anexos' da ocorrência
      await FirebaseFirestore.instance
          .collection('ocorrencias')
          .doc(ocorrenciaId)
          .update({
        'anexos': FieldValue.arrayUnion([url]),
      });
    }

    final List<String> audioUrls = [];
    final File? audioFile = audio ?? _audioFile;
    if (audioFile != null && audioFile.existsSync()) {
      final name = audioFile.path.split('/').last;
      final ref = storage
          .ref()
          .child('sos/$ownerUid/$ocorrenciaId/audio/$name');
      await ref.putFile(audioFile);
      final url = await ref.getDownloadURL();
      audioUrls.add(url);

      // Registrar no Firestore no campo 'anexos' da ocorrência
      await FirebaseFirestore.instance
          .collection('ocorrencias')
          .doc(ocorrenciaId)
        .update({
      'anexos': FieldValue.arrayUnion([url]),
      'audioUrl': url,
    });
    }

    // Limpar buffers locais
    _photos.clear();
    _audioFile = null;
  }

  /// Apenas para tudo (sem upload)
  Future<File?> stop() async {
    if (!_started && _audioFile != null) return _audioFile;

    _started = false;

    _photoTimer?.cancel();
    _photoTimer = null;
    _audioLimitTimer?.cancel();
    _audioLimitTimer = null;

    // Parar áudio
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      if (path != null) {
        _audioFile = File(path);
      }
    }

    // Dispensar câmera
    await _camera?.dispose();
    _camera = null;

    return _audioFile;
  }

  // ====== INTERNALS ======

  Future<void> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    final cam = await Permission.camera.request();
    if (!mic.isGranted || !cam.isGranted) {
      throw StateError('Permissões de CÂMERA e MICROFONE são necessárias.');
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    CameraDescription? back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.isNotEmpty
          ? cameras.first
          : throw StateError('Nenhuma câmera disponível'),
    );

    _camera = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _camera!.initialize();
  }

  Future<void> _takePhoto() async {
    if (_camera == null || !_camera!.value.isInitialized) return;

    final dir = await _sosDir();
    final name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '${dir.path}/$name';

    final xFile = await _camera!.takePicture();
    // Salva como está (Camera já entrega JPEG).
    final out = File(path);
    await out.writeAsBytes(await xFile.readAsBytes(), flush: true);
    _photos.add(out);
  }

  Future<void> _recordAudioLimited({
    Future<void> Function()? onMaxDurationReached,
  }) async {
    if (await _recorder.isRecording()) return;

    final dir = await _sosDir();
    final name = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '${dir.path}/$name';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    // Para automaticamente após audioDuration
    _audioLimitTimer = Timer(audioDuration, () async {
      if (await _recorder.isRecording()) {
        final p = await _recorder.stop();
        _audioFile = p != null ? File(p) : File(path);
      }
      
      // Chama callback para que a tela finalize e envie a mídia
      if (onMaxDurationReached != null) {
        await onMaxDurationReached();
      }
    });
  }

  Future<Directory> _sosDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sos_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
