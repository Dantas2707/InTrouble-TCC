import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'firestore.dart';

/// Serviço responsável por atualizar periodicamente a localização do SOS aberto.
/// Mantém um stream do [Geolocator] ativo mesmo quando o app vai para segundo plano
/// (via [ForegroundNotificationConfig] no Android) e envia as posições para o Firestore
/// através de [FirestoreService.updateLocalizacaoSosAberto].
class SosLocationTracker with WidgetsBindingObserver {
  SosLocationTracker._({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService();

  static final SosLocationTracker _instance = SosLocationTracker._();

  factory SosLocationTracker({FirestoreService? firestoreService}) {
    if (firestoreService != null) {
      _instance._firestoreService = firestoreService;
    }
    return _instance;
  }

  FirestoreService _firestoreService;
  StreamSubscription<Position>? _positionSubscription;
  bool _tracking = false;

  /// Intervalo desejado entre cada atualização enviada ao Firestore.
  final Duration updateInterval = const Duration(seconds: 5);

  bool get isTracking => _tracking;

  /// Inicia o monitoramento de localização, caso ainda não esteja ativo.
  Future<void> start() async {
    // Verifica permissão de localização antes de iniciar o monitoramento
    if (!await _garantirPermissaoLocalizacao()) {
      return;
    }

    if (_tracking) return;

    _tracking = true;
    WidgetsBinding.instance.addObserver(this);

    // Envia imediatamente a posição atual e depois mantém a stream ativa.
    await _sendCurrentPosition();
    _listenToPositionStream();
  }

  /// Cancela o monitoramento.
  Future<void> stop() async {
    if (!_tracking) return;

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _tracking = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Começa a escutar a posição do usuário e envia as atualizações para o Firestore.
  void _listenToPositionStream() {
    _positionSubscription?.cancel();

    final settings = _buildLocationSettings();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) {
      _firestoreService.updateLocalizacaoSosAberto(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }, onError: (Object error) {
      // Em caso de erro (ex.: serviço desligado), tenta reiniciar após um tempo.
      _restartStreamWithDelay();
    });
  }

  /// Envia a posição atual para o Firestore.
  Future<void> _sendCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _firestoreService.updateLocalizacaoSosAberto(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      // Ignorar erros pontuais; o stream cuidará das próximas atualizações.
    }
  }

  /// Configura as opções para obter as localizações dependendo da plataforma.
  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: updateInterval,
        // Notificação obrigatória para capturar localização em segundo plano no Android.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'SOS em andamento',
          notificationText: 'Monitorando sua localização em tempo real.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  /// Tenta reiniciar o stream de localização após um erro.
  void _restartStreamWithDelay() {
    if (!_tracking) return;

    Future.delayed(const Duration(seconds: 5), () {
      if (_tracking) {
        _listenToPositionStream();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_tracking) return;

    if (state == AppLifecycleState.resumed) {
      // Reforça que o stream continua ativo ao retornar para o app.
      _listenToPositionStream();
    }
  }

  /// Verifica e solicita permissões de localização.
  Future<bool> _garantirPermissaoLocalizacao() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("GPS não ativado!");
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      print("Permissão de localização negada!");
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      print("Permissão negada permanentemente!");
      // Direcionar o usuário para as configurações do app
      await openAppSettings();
      return false;
    }

    return true;
  }

  /// Abre as configurações de localização do dispositivo
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } on PlatformException catch (e) {
      print("Erro ao abrir configurações de localização: $e");
    }
  }

  /// Abre as configurações do app no dispositivo
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } on PlatformException catch (e) {
      print("Erro ao abrir configurações do app: $e");
    }
  }
}
