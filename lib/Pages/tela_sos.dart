import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crud/services/firestore.dart';
import 'package:crud/services/sos_location_tracker.dart';
import 'package:crud/services/sos_media_recorder.dart';
import 'package:crud/services/enviar_email.dart';
import 'package:crud/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

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

  StreamSubscription<PhoneState>? _phoneStateSub;
  List<Map<String, String>> _filaGuardioes = [];
  int _indiceGuardiaoAtual = 0;
  bool _loopLigacoesAtivo = false;
  bool _chamadaConectada = false;
  PhoneStateStatus? _ultimoStatusTelefone;
  DateTime? _ultimaTrocaGuardiao;

  bool _loading = false;
  bool _sosAtivo = false;
  bool _finalizandoSos = false; // trava para evitar finalizações duplicadas

  /// ID da ocorrência SOS aberta (para vincular upload e finalizar)
  String? _ocorrenciaId;

  // Timer de segurança para finalizar o SOS caso chegue ao limite de áudio
  Timer? _autoFinalizacaoTimer;

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
      if (!mounted) return;
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

  /// Busca e-mail, nome e telefone dos guardiões pelo id.
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
        final telefone = (data['numerotelefone'] ?? '').toString().trim();

        if (email.isNotEmpty || telefone.isNotEmpty) {
          contatos.add({
            'email': email,
            'nome': nome,
            'telefone': telefone,
          });
        }
      } catch (e) {
        debugPrint('Erro ao buscar guardião $guardiaoId: $e');
      }
    }

    return contatos;
  }

  Future<bool> _garantirPermissaoLigacao() async {
    final status = await Permission.phone.status;

    if (status.isGranted) return true;

    final novoStatus = await Permission.phone.request();

    if (!novoStatus.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para ligar automaticamente para o guardião, '
            'permita o acesso ao recurso de telefone nas permissões do app.',
          ),
        ),
      );
    }

    return novoStatus.isGranted;
  }

  Future<void> _ligarDiretoParaGuardiaoPrincipal(
      List<Map<String, String>> contatos) async {
    if (contatos.isEmpty) return;

    // Garante permissão CALL_PHONE
    final permitido = await _garantirPermissaoLigacao();
    if (!permitido) return;

    // Pega o primeiro guardião com telefone cadastrado
    final contato = contatos.firstWhere(
      (c) => (c['telefone'] ?? '').trim().isNotEmpty,
      orElse: () => {},
    );

    final numero = (contato['telefone'] ?? '').toString().trim();

    if (numero.isEmpty) {
      debugPrint('Nenhum guardião com telefone cadastrado.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível efetuar a ligação: '
              'nenhum guardião com telefone cadastrado.',
            ),
          ),
        );
      }
      return;
    }

    try {
      await FlutterPhoneDirectCaller.callNumber(numero);
    } catch (e) {
      debugPrint('Erro ao tentar ligar para o guardião $numero: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ocorreu um erro ao iniciar a ligação para o guardião.',
            ),
          ),
        );
      }
    }
  }

  String normalizarTelefoneBR(String input) {
    // tira espaços, traços, parênteses etc.
    var digits = input.replaceAll(RegExp(r'\D'), '');

    // se já vier com 55 + DDD + número
    if (digits.startsWith('55') && digits.length >= 12) {
      return '+$digits';
    }

    // se vier só com DDD+numero (ex: 61984250137)
    if (digits.length >= 10 && !digits.startsWith('55')) {
      return '+55$digits';
    }

    // fallback
    return '+$digits';
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
      final query =
          await col.where('nome', isEqualTo: 'Pedido de socorro').get();

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

  Future<void> _ligarParaGuardiaoPrincipal(
      List<Map<String, String>> contatos) async {
    if (contatos.isEmpty) return;

    // pega o primeiro com telefone preenchido
    final contatoComTelefone = contatos.firstWhere(
      (c) => (c['telefone'] ?? '').isNotEmpty,
      orElse: () => {},
    );

    final telefone = (contatoComTelefone['telefone'] ?? '').trim();
    if (telefone.isEmpty) {
      debugPrint('Nenhum guardião com telefone cadastrado.');
      return;
    }

    final uri = Uri(scheme: 'tel', path: telefone);

    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        await launchUrl(uri); // abre o discador já com o número
      } else {
        debugPrint('Não foi possível iniciar a chamada para $telefone');
      }
    } catch (e) {
      debugPrint('Erro ao tentar ligar para $telefone: $e');
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
      final query = await col
          .where('nome', isEqualTo: 'Pedido de socorro finalizado')
          .get();

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
  //          LOOP DE LIGAÇÕES SEQUENCIAIS PARA GUARDIÕES
  // =========================================================

   Future<void> _iniciarLigacoesSequenciais(
      List<Map<String, String>> contatos) async {
    final contatosComTelefone = contatos.where((c) {
      final tel = (c['telefone'] ?? '').trim();
      return tel.isNotEmpty;
    }).toList();

    if (contatosComTelefone.isEmpty) {
      debugPrint('Nenhum guardião com telefone cadastrado na fila.');
      return;
    }

    final permitido = await _garantirPermissaoLigacao();
    if (!permitido) return;

    _filaGuardioes = contatosComTelefone;
    _indiceGuardiaoAtual = 0;
    _loopLigacoesAtivo = true;
    _ultimaTrocaGuardiao = null;
    _ultimoStatusTelefone = null;

    await _phoneStateSub?.cancel();
    _phoneStateSub = PhoneState.stream.listen((event) {
      final status = event.status;
      debugPrint(
        'STATUS LIGACAO: $status | loop=$_loopLigacoesAtivo | '
        'indice=$_indiceGuardiaoAtual | tamanhoFila=${_filaGuardioes.length}',
      );

      if (!_loopLigacoesAtivo) return;

      if (status == PhoneStateStatus.CALL_STARTED) {
        _chamadaConectada = true;
      }

      if (status == PhoneStateStatus.CALL_ENDED) {
        final agora = DateTime.now();

        // Evita tratar o mesmo fim de chamada mais de uma vez
        if (_ultimaTrocaGuardiao != null &&
            agora.difference(_ultimaTrocaGuardiao!).inMilliseconds < 1500) {
          debugPrint('CALL_ENDED ignorado (duplicado em menos de 1.5s)');
          return;
        }

        _ultimaTrocaGuardiao = agora;

        if (!_sosAtivo) {
          debugPrint(
              'CALL_ENDED recebido mas SOS não está mais ativo. Encerrando loop de ligações.');
          _pararLoopLigacoes();
          return;
        }

        _chamarProximoGuardiao();
      }

      _ultimoStatusTelefone = status;
    });

    // Dispara a primeira ligação
    await _chamarGuardiaoAtual();
  }

    Future<void> _chamarGuardiaoAtual() async {
    if (!_loopLigacoesAtivo || _filaGuardioes.isEmpty) return;

    final contato = _filaGuardioes[_indiceGuardiaoAtual];
    final telBruto = (contato['telefone'] ?? '').trim();

    if (telBruto.isEmpty) {
      debugPrint(
        'Guardião no índice $_indiceGuardiaoAtual está sem telefone. Indo para o próximo.',
      );
      await _chamarProximoGuardiao();
      return;
    }

    final numero = normalizarTelefoneBR(telBruto);
    debugPrint(
      'Ligando para guardião $_indiceGuardiaoAtual de '
      '${_filaGuardioes.length} -> $numero',
    );

    try {
      await FlutterPhoneDirectCaller.callNumber(numero);
    } catch (e) {
      debugPrint('Erro ao tentar ligar para $numero: $e');
      await _chamarProximoGuardiao();
    }
  }


    Future<void> _chamarProximoGuardiao() async {
    if (!_loopLigacoesAtivo || _filaGuardioes.isEmpty) return;

    _indiceGuardiaoAtual = (_indiceGuardiaoAtual + 1) % _filaGuardioes.length;
    debugPrint(
      'CALL_ENDED: indo para o próximo guardião. '
      'Novo índice=$_indiceGuardiaoAtual de ${_filaGuardioes.length}',
    );

    // Dá um respiro pro Android encerrar de vez a ligação anterior
    await Future.delayed(const Duration(seconds: 2));

    if (!_loopLigacoesAtivo || !_sosAtivo) {
      debugPrint(
        'Loop de ligações cancelado durante o delay. '
        'Não vou ligar para o próximo.',
      );
      return;
    }

    await _chamarGuardiaoAtual();
  }


  void _pararLoopLigacoes() {
    debugPrint('Parando loop de ligações e cancelando listener de telefone.');
    _loopLigacoesAtivo = false;
    _phoneStateSub?.cancel();
    _phoneStateSub = null;
  }

  // =========================================================

  Future<void> _onToggleSOS() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Usuário não autenticado.');

      if (_sosAtivo) {
        await _finalizarSosComMidia(disparadoAutomatico: false);
      } else {
        await _iniciarSos(uid);
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

  Future<void> _iniciarSos(String uid) async {
    // 1) Garantir permissão de localização + serviço ligado
    final ok = await garantirPermissaoLocalizacao(context);
    if (!ok) return;

    // 2) Obter posição atual
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

    // 3) Buscar nome do usuário (só para salvar/telemetria)
    String nomeUsuario = 'Usuário';
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('usuario').doc(uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        nomeUsuario = (data['nome'] ?? nomeUsuario).toString();
      }
    } catch (e) {
      debugPrint('Erro ao buscar nome do usuário para SOS: $e');
    }

    // 4) Buscar IDs dos guardiões aceitos/ativos
    final guardioesIds = await _buscarGuardioesAceitosEAtivos(uid);

    // 4.1) Carregar dados completos dos guardiões (email, nome, telefone)
    final contatosGuardioes = await _buscarContatosGuardioes(guardioesIds);

    const textoSocorroPadrao =
        'Atenção! Estou sob ameaça! Preciso de ajuda imediatamente.';

    // 5) Abrir ocorrência SOS no Firestore
    final agora = DateTime.now();
    final id = await _fs.addOcorrencia(
      'SOS', // tipoOcorrencia
      'Gravíssima', // gravidade
      'SOS acionado pelo usuário $nomeUsuario', // relato
      textoSocorroPadrao, // texto socorro
      true, // enviarParaGuardiao (se você usa essa flag em outro lugar)
      anexosLocais: const [],
      idGuardiao: guardioesIds,
      ownerUid: uid,
      latitudeInicial: pos.latitude,
      longitudeInicial: pos.longitude,
      dataHoraAbertura: agora,
    );
    _ocorrenciaId = id;

    // 6) Enviar e-mail de SOS para os guardiões
    _enviarEmailsSosGuardioes(guardioesIds, textoSocorroPadrao);

    // 6.1) Iniciar loop de ligações sequenciais para os guardiões
    await _iniciarLigacoesSequenciais(contatosGuardioes);

    // 7) Iniciar rastreamento de localização + gravação de mídia
    _media ??= await _obterMediaRecorder();
    await _tracker.start();
    await _media!.start(
      onMaxDurationReached: () =>
          _finalizarSosComMidia(disparadoAutomatico: true),
    );

    // 8) Fallback extra: agenda finalização mesmo se callback não disparar
    _autoFinalizacaoTimer?.cancel();
    _autoFinalizacaoTimer = Timer(
      _media!.audioDuration,
      () => _finalizarSosComMidia(disparadoAutomatico: true),
    );

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

  Future<void> _finalizarSosComMidia({required bool disparadoAutomatico}) async {
    // Finalização única do SOS que sempre envia o áudio gravado
    if (_finalizandoSos) return;
    _pararLoopLigacoes();
    _finalizandoSos = true;

    try {
      _autoFinalizacaoTimer?.cancel();
      await _tracker.stop();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        await _media?.stop();
        return;
      }

      if (_ocorrenciaId != null) {
        await _media?.stopAndUpload(
          ocorrenciaId: _ocorrenciaId!,
          ownerUid: uid,
        );

        await _fs.finalizarOcorrencia(_ocorrenciaId!);

        final guardioesIds = await _buscarGuardioesAceitosEAtivos(uid);
        _enviarEmailsSosFinalizado(guardioesIds);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                disparadoAutomatico
                    ? 'Tempo máximo atingido. SOS finalizado e mídia enviada.'
                    : 'SOS finalizado e mídia enviada.',
              ),
            ),
          );
        } else {
          await _media?.stop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao finalizar SOS: ${e.toString()}',
            ),
          ),
        );
      }
    } finally {
      _finalizandoSos = false;
    }
  }

  @override
  void dispose() {
    _tracker.stop();
    _media?.stop();
    _autoFinalizacaoTimer?.cancel();
    _phoneStateSub?.cancel();
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
                      color:
                          ativo ? Colors.red.shade700 : Colors.grey.shade800,
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
