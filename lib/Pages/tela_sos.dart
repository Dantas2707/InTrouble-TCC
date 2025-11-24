import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crud/services/firestore.dart';
import 'package:crud/services/sos_location_tracker.dart';
import 'package:crud/services/sos_media_recorder.dart';

// ===================== PALETA =====================
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kRosaClaro      = Color(0xFFF2C4CD); // #F2C4CD
const kRosaMedio      = Color(0xFFD9B4BB); // #D9B4BB
const kRosaSuave      = Color(0xFFF2C4C4); // #F2C4C4
const kCinzaClaro     = Color(0xFFF2F2F2); // #F2F2F2

class TelaVitimaSOS extends StatefulWidget {
  const TelaVitimaSOS({Key? key}) : super(key: key);

  @override
  _TelaVitimaSOSState createState() => _TelaVitimaSOSState();
}

class _TelaVitimaSOSState extends State<TelaVitimaSOS> {
  final FirestoreService _fs = FirestoreService();
  final _tracker = SosLocationTracker();

  // Recorder é opcional e criado conforme config do ADM
  SosMediaRecorder? _media;

  bool _loading = false;
  bool _sosAtivo = false;

  /// ID da ocorrência SOS aberta (para vincular upload e finalizar)
  String? _ocorrenciaId;

  @override
  void initState() {
    super.initState();
    _escutarStatusSOS();
  }

  /// Escuta apenas ocorrências do tipo 'SOS' e status 'aberto'
  void _escutarStatusSOS() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('ocorrencias')
        .where('ownerUid', isEqualTo: uid)
        .where('tipoOcorrencia', isEqualTo: 'SOS')
        .where('status', isEqualTo: 'aberto')
        .limit(1)
        .snapshots()
        .listen((snap) {
      final ativo = snap.docs.isNotEmpty;
      setState(() {
        _sosAtivo = ativo;
        _ocorrenciaId = ativo ? snap.docs.first.id : null;
      });
    });
  }

  /// Cria o recorder respeitando a configuração do ADM no Firestore.
  Future<SosMediaRecorder> _obterMediaRecorder() async {
    try {
      return await SosMediaRecorder.fromRemoteConfig();
    } catch (e) {
      // Fallback para configuração padrão
      return SosMediaRecorder(
        photoInterval: const Duration(minutes: 1),
        audioDuration: const Duration(minutes: 1),
        jpegQuality: 85,
      );
    }
  }

  // =========================================================
  //              HELPERS DE GUARDIÕES
  // =========================================================

  /// Busca IDs dos guardiões do usuário com status 'aceito' ou 'ativo'.
  Future<List<String>> _buscarGuardioesAceitosEAtivos(String uid) async {
    final aceitosSnap = await FirebaseFirestore.instance
        .collection('guardiões')
        .where('id_usuario', isEqualTo: uid)
        .where('status', isEqualTo: 'aceito')
        .get();

    final ativosSnap = await FirebaseFirestore.instance
        .collection('guardiões')
        .where('id_usuario', isEqualTo: uid)
        .where('status', isEqualTo: 'ativo')
        .get();

    final idsSet = <String>{};

    for (final doc in aceitosSnap.docs) {
      final idG = (doc['id_guardiao'] as String?) ?? '';
      if (idG.isNotEmpty) idsSet.add(idG);
    }

    for (final doc in ativosSnap.docs) {
      final idG = (doc['id_guardiao'] as String?) ?? '';
      if (idG.isNotEmpty) idsSet.add(idG);
    }

    return idsSet.toList();
  }

  // =========================================================

  Future<void> _onToggleSOS() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Usuário não autenticado.');

      if (_sosAtivo) {
        // === FINALIZAR SOS ===
        await _tracker.stop(); // Para rastreamento de localização

        if (_ocorrenciaId != null) {
          if (_media != null) {
            await _media!.stopAndUpload(
              ocorrenciaId: _ocorrenciaId!,
              ownerUid: uid,
            );
          } else {
            await _media?.stop();
          }

          // Atualiza status para "finalizado" (Cloud Function onSosFinalizado cuida do SMS)
          await _fs.finalizarOcorrencia(_ocorrenciaId!);
        } else {
          await _media?.stop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS finalizado e mídia enviada.')),
          );
        }
      } else {
        // === ACIONAR SOS ===

        // 1) Posição atual (pode pedir permissão de localização)
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // 2) Buscar nome do usuário (só para salvar/telemetria, SMS é backend)
        String nomeUsuario = 'Usuário';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('usuario')
              .doc(uid)
              .get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data() as Map<String, dynamic>;
            nomeUsuario = (data['nome'] ?? nomeUsuario).toString();
          }
        } catch (e) {
          debugPrint('Erro ao buscar nome do usuário para SOS: $e');
        }

        // 3) Buscar IDs dos guardiões aceitos/ativos
        final guardioesIds = await _buscarGuardioesAceitosEAtivos(uid);

        // 4) Abrir ocorrência SOS no Firestore usando o MESMO addOcorrencia
        //    Cloud Function onSosCreated vai enxergar esse doc e disparar os SMS
        final agora = DateTime.now();
        final id = await _fs.addOcorrencia(
          'SOS',
          'Gravíssima',
          'SOS acionado pelo usuário $nomeUsuario',
          'Atenção! Estou sob ameaça! Preciso de ajuda imediatamente.',
          true, // enviarParaGuardiao (se você usa essa flag em outro lugar)
          anexosLocais: const [],
          idGuardiao: guardioesIds,
          ownerUid: uid,
          isSos: true,
          latitudeInicial: pos.latitude,
          longitudeInicial: pos.longitude,
          dataHoraAbertura: agora,
        );
        _ocorrenciaId = id;

        // 5) Mídia + rastreamento locais (apenas para evidências)
        _media ??= await _obterMediaRecorder();
        await _tracker.start();
        await _media!.start();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'SOS acionado. Capturando mídia e localização...',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tracker.stop();
    _media?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool ativo = _sosAtivo;

    return Scaffold(
      // AppBar no padrão da paleta
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kRosaClaro,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'SOS - Vítima',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Fundo com gradiente suave
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kCinzaClaro, kRosaMuitoClaro],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Card de instrução/estado
                  Card(
                    color: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            ativo
                                ? 'SOS em andamento'
                                : 'Acione o SOS em situação de risco',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color.fromARGB(255, 82, 60, 66),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ativo
                                ? 'Estamos enviando sua localização e registrando evidências para os seus guardiões.'
                                : 'Ao acionar o SOS, sua localização será compartilhada e mídias poderão ser gravadas para sua segurança.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color.fromARGB(255, 110, 90, 96),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: ativo
                                      ? Colors.red.shade100
                                      : kRosaClaro.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: ativo
                                        ? Colors.red.shade400
                                        : kRosaClaro,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      ativo
                                          ? Icons.warning_amber_rounded
                                          : Icons.shield_outlined,
                                      size: 18,
                                      color: ativo
                                          ? Colors.red.shade700
                                          : const Color.fromARGB(
                                              255, 120, 96, 102),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      ativo ? 'SOS ATIVO' : 'SOS DESATIVADO',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: ativo
                                            ? Colors.red.shade700
                                            : const Color.fromARGB(
                                                255, 120, 96, 102),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Botão circular SOS com "glow"
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ativo
                              ? Colors.red.withOpacity(0.5)
                              : Colors.red.withOpacity(0.3),
                          blurRadius: 22,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 150,
                      height: 150,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onToggleSOS,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              ativo ? Colors.red.shade700 : Colors.red,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(24),
                          elevation: 8,
                          disabledBackgroundColor: Colors.redAccent,
                          disabledForegroundColor: Colors.white70,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    ativo ? Icons.stop : Icons.warning,
                                    size: 44,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    ativo ? 'Finalizar' : 'Acionar',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Texto auxiliar
                  Text(
                    ativo
                        ? 'Toque em “Finalizar” apenas quando estiver em segurança.'
                        : 'Use este recurso somente em situações reais de risco.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ativo
                          ? Colors.red.shade700
                          : Colors.grey.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
