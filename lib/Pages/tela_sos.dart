import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crud/services/firestore.dart';
import 'package:crud/services/sos_location_tracker.dart';
import 'package:crud/services/sos_media_recorder.dart';
import 'package:crud/services/enviar_email.dart';
import 'package:crud/theme/app_colors.dart';

const kRosaMuitoClaro = AppColors.primaryLight;
const kRosaClaro = AppColors.primary;
const kRosaMedio = AppColors.primaryMedium;
const kRosaSuave = AppColors.primarySoft;
const kCinzaClaro = AppColors.grayLight;

Future<bool> garantirPermissaoLocalizacao(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ative a localização'),
        content: const Text(
          'Para usar o SOS, é necessário que o GPS esteja ativo. Ative a localização nas configurações rápidas do seu aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    return false;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Para usar o SOS, autorize o acesso à localização nas permissões do aplicativo.',
        ),
      ),
    );
    return false;
  }

  if (permission == LocationPermission.deniedForever) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissão de localização necessária'),
        content: const Text(
          'Você negou a permissão de localização para o aplicativo.\n\nPara usar o SOS, vá em:\nConfigurações do celular > Aplicativos > [nome do app] > Permissões\ne ative a opção "Localização".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
    return false;
  }

  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

class TelaVitimaSOS extends StatefulWidget {
  const TelaVitimaSOS({Key? key}) : super(key: key);

  @override
  _TelaVitimaSOSState createState() => _TelaVitimaSOSState();
}

class _TelaVitimaSOSState extends State<TelaVitimaSOS> {
  final FirestoreService _fs = FirestoreService();
  final _tracker = SosLocationTracker();
  final _emailSvc = EmailBackendService();
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
        .where('status', whereIn: ['aceito', 'ativo'])
        .get();

    final idsSet = <String>{};

    for (final doc in aceitosSnap.docs) {
      final idG = (doc['id_guardiao'] as String?) ?? '';
      if (idG.isNotEmpty) idsSet.add(idG);
    }

    return idsSet.toList();
  }

  /// Busca e-mail e nome dos guardiões pelo id.
   /// Busca e-mail e nome dos guardiões pelo id.
  Future<List<Map<String, String>>> _buscarContatosGuardioes(
      List<String> guardioesIds) async {
    final contatos = <Map<String, String>>[];

    for (final guardiaoId in guardioesIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuario')
            .doc(guardiaoId)
            .get();

        if (!doc.exists || doc.data() == null) continue;

        final data = doc.data() as Map<String, dynamic>;
        final email = (data['email'] ?? '').toString().trim();
        final nome = (data['nome'] ?? 'Guardião').toString();

        if (email.isNotEmpty) {
          contatos.add({'email': email, 'nome': nome});
        }
      } catch (e) {
        debugPrint('Erro ao buscar guardião $guardiaoId: $e');
      }
    }

    return contatos;
  }

  /// Busca o template de e-mail do SOS na coleção `textosEmails`.
  Future<Map<String, String>> _tplSosGuardiao() async {
    const assuntoFallback = '🚨 SOS acionado - InTrouble';
    const bodyFallback =
        'Olá {nomeGuardiao}, {nome} acionou o SOS no app InTrouble. Mensagem: {socorro}. Hora: {hora}.';
    const htmlFallback =
        '<p>Olá {nomeGuardiao},</p><p><b>{nome}</b> acionou o SOS no app InTrouble.</p><p><b>Mensagem:</b> {socorro}</p><p><b>Horário:</b> {hora}</p>';

    try {
      final col = FirebaseFirestore.instance.collection('textosEmails');
      final query = await col.where('nome', isEqualTo: 'Pedido de socorro').get();

      if (query.docs.isEmpty) {
        return {
          'assunto': assuntoFallback,
          'body': bodyFallback,
          'htmlBody': htmlFallback,
        };
      }

      final ativos = query.docs.where((d) {
        final data = d.data();
        return (data['inativar'] == false);
      }).toList();

      if (ativos.isEmpty) {
        return {
          'assunto': assuntoFallback,
          'body': bodyFallback,
          'htmlBody': htmlFallback,
        };
      }

      final data = ativos.first.data();
      final textoEmail = (data['textoEmail'] ?? '').toString().trim();
      final assunto = (data['assunto'] ?? assuntoFallback).toString();
      final textoPlano = _textoSemHtml(textoEmail);
      final bodyFromTemplate = textoEmail.isNotEmpty
          ? (textoPlano.isNotEmpty ? textoPlano : textoEmail)
          : bodyFallback;

      return {
        'assunto': assunto,
        'body': bodyFromTemplate,
        'htmlBody': textoEmail.isNotEmpty ? textoEmail : htmlFallback,
      };
    } catch (e) {
      debugPrint('Erro ao buscar template de SOS: $e');
      return {
        'assunto': assuntoFallback,
        'body': bodyFallback,
        'htmlBody': htmlFallback,
      };
    }
  }

  /// Remove as tags HTML para montar um corpo de texto simples.
  String _textoSemHtml(String html) {
    final plain = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return plain.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Busca o template de e-mail para finalização do SOS.
  Future<Map<String, String>> _tplSosGuardiaoFinalizado() async {
    const assuntoFallback = '✅ SOS finalizado - InTrouble';
    const bodyFallback =
        'Olá {nomeGuardiao}, {nome} finalizou o SOS no app InTrouble. Horário: {hora}.';
    const htmlFallback =
        '<p>Olá {nomeGuardiao},</p><p><b>{nome}</b> finalizou o SOS no app InTrouble.</p><p><b>Horário:</b> {hora}</p>';

    try {
      final col = FirebaseFirestore.instance.collection('textosEmails');
      final query = await col.where('nome', isEqualTo: 'Pedido de socorro finalizado').get();

      if (query.docs.isEmpty) {
        return {
          'assunto': assuntoFallback,
          'body': bodyFallback,
          'htmlBody': htmlFallback,
        };
      }

      final ativos = query.docs.where((d) {
        final data = d.data();
        return (data['inativar'] == false);
      }).toList();

      if (ativos.isEmpty) {
        return {
          'assunto': assuntoFallback,
          'body': bodyFallback,
          'htmlBody': htmlFallback,
        };
      }

      final data = ativos.first.data();
      final textoEmail = (data['textoEmail'] ?? '').toString().trim();
      final assunto = (data['assunto'] ?? assuntoFallback).toString();
      final textoPlano = _textoSemHtml(textoEmail);
      final bodyFromTemplate = textoEmail.isNotEmpty
          ? (textoPlano.isNotEmpty ? textoPlano : textoEmail)
          : bodyFallback;

      return {
        'assunto': assunto,
        'body': bodyFromTemplate,
        'htmlBody': textoEmail.isNotEmpty ? textoEmail : htmlFallback,
      };
    } catch (e) {
      debugPrint('Erro ao buscar template de finalização do SOS: $e');
      return {
        'assunto': assuntoFallback,
        'body': bodyFallback,
        'htmlBody': htmlFallback,
      };
    }
  }

  Future<void> _enviarEmailsSosGuardioes(
    List<String> guardioesIds,
    String textoSocorro,
  ) async {
    if (guardioesIds.isEmpty) return;

    try {
      final contatos = await _buscarContatosGuardioes(guardioesIds);
      if (contatos.isEmpty) return;

      final tpl = await _tplSosGuardiao();
      final assunto = tpl['assunto'] ?? '🚨 SOS acionado - InTrouble';
      final body = tpl['body']?.isNotEmpty == true
          ? tpl['body']!
          : 'Olá {nomeGuardiao}, {nome} acionou o SOS no app InTrouble. Mensagem: {socorro}. Hora: {hora}.';
      final htmlBody = tpl['htmlBody'];

      for (final contato in contatos) {
        final email = contato['email'] ?? '';
        final nomeGuardiao = contato['nome'];

        if (email.isEmpty) continue;

        try {
          await _emailSvc.enviarEmailViaBackend(
            to: email,
            subject: assunto,
            body: body,
            htmlBody: htmlBody,
            nomeGuardiao: nomeGuardiao,
            textoSocorro: textoSocorro,
          );
        } catch (e) {
          debugPrint('Erro ao enviar e-mail de SOS para $email: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro geral ao enviar e-mails de SOS: $e');
    }
  }

  Future<void> _enviarEmailsSosFinalizado(List<String> guardioesIds) async {
    if (guardioesIds.isEmpty) return;

    try {
      final contatos = await _buscarContatosGuardioes(guardioesIds);
      if (contatos.isEmpty) return;

      final tpl = await _tplSosGuardiaoFinalizado();
      final assunto = tpl['assunto'] ?? '✅ SOS finalizado - InTrouble';
      final body = tpl['body']?.isNotEmpty == true
          ? tpl['body']!
          : 'Olá {nomeGuardiao}, {nome} finalizou o SOS no app InTrouble. Horário: {hora}.';
      final htmlBody = tpl['htmlBody'];

      for (final contato in contatos) {
        final email = contato['email'] ?? '';
        final nomeGuardiao = contato['nome'];

        if (email.isEmpty) continue;

        try {
          await _emailSvc.enviarEmailViaBackend(
            to: email,
            subject: assunto,
            body: body,
            htmlBody: htmlBody,
            nomeGuardiao: nomeGuardiao,
          );
        } catch (e) {
          debugPrint('Erro ao enviar e-mail de finalização de SOS para $email: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro geral ao enviar e-mails de finalização do SOS: $e');
    }
  }


  // =========================================================

  Future<void> _onToggleSOS() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Usuário não autenticado.');

      if (_sosAtivo) {
        // === FINALIZAR SOS ===
        final guardioesIds = await _buscarGuardioesAceitosEAtivos(uid);
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

          await _fs.finalizarOcorrencia(_ocorrenciaId!);
        } else {
          await _media?.stop();
        }

        _enviarEmailsSosFinalizado(guardioesIds);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS finalizado e mídia enviada.')),
          );
        }
      } else {
        // === ACIONAR SOS ===

        final ok = await garantirPermissaoLocalizacao(context);
        if (!ok) return;

        // 1) Posição atual (pode pedir permissão de localização)
        late final Position pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
        } on PermissionDeniedException catch (e) {
          debugPrint('Permissão de localização negada durante o SOS: $e');
          return;
        } catch (e) {
          debugPrint('Erro ao obter localização para SOS: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Não foi possível obter sua localização. Verifique o GPS e tente novamente.',
                ),
              ),
            );
          }
          return;
        }
        // 2) Buscar nome do usuário (só para salvar/telemetria)
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

        const textoSocorroPadrao =
            'Atenção! Estou sob ameaça! Preciso de ajuda imediatamente.';
        
        // 4) Abrir ocorrência SOS no Firestore
        final agora = DateTime.now();
        final id = await _fs.addOcorrencia(
          'SOS',
          'Gravíssima',
          'SOS acionado pelo usuário $nomeUsuario',
          textoSocorroPadrao,
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

        // 5) Enviar e-mail de SOS para os guardiões
        _enviarEmailsSosGuardioes(guardioesIds, textoSocorroPadrao);

        // 6) Mídia + rastreamento locais (apenas para evidências)
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
          const SnackBar(
            content: Text(
              'Não foi possível completar a ação do SOS. Tente novamente em instantes.',
            ),
          ),
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
