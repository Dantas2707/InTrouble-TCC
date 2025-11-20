import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crud/services/firestore.dart';
import 'package:crud/Pages/tela_config.dart';
import 'tela_usuario.dart';
import 'tela_tipo_ocorrencia.dart';
import 'tela_configuracoes.dart';
import 'tela_registrar_ocorrencia.dart';
import 'tela_ocorrencia.dart';
import 'tela_login.dart';
import 'tela_localizacao.dart';
import 'tela_sos.dart';
import 'perfil_usuario_e_guardiao.dart';
import 'tela_ocorrencias_acompanhar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String adminEmail = 'aplicativo2025tcc@gmail.com';
  final FirestoreService _fs = FirestoreService();

  // Paleta de cores
  static const Color _colF2DFE0 = Color(0xFFF2DFE0);
  static const Color _colF2C4CD = Color(0xFFF2C4CD);
  static const Color _colD9B4BB = Color(0xFFD9B4BB);
  static const Color _colF2C4C4 = Color(0xFFF2C4C4);
  static const Color _colF2F2F2 = Color(0xFFF2F2F2);

  bool _temGuardiao = false; // alguém me guarda
  bool _guardoAlguem = false; // eu guardo alguém
  bool _carregandoRelacoes = true;
  late String _uid;

  /// Nome do usuário vindo da coleção `usuario` (apenas o primeiro nome)
  String _nomeUsuario = '';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }
    _uid = user.uid;

    // Escuta o perfil pra pegar o nome certinho do Firestore
    _ouvirPerfil();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _solicitarPermissaoInicial();
    });
    _monitorarGuardiao();
  }

  /// Escuta o documento do usuário em `usuario/{uid}` e atualiza o primeiro nome
  void _ouvirPerfil() {
    _fs.usuario.doc(_uid).snapshots().listen((doc) {
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final nomeCompleto = (data['nome'] ?? '').toString().trim();
      if (nomeCompleto.isEmpty) return;

      // Pega só o primeiro nome (até o primeiro espaço)
      String primeiroNome = nomeCompleto;
      if (nomeCompleto.contains(' ')) {
        primeiroNome = nomeCompleto.split(RegExp(r'\s+')).first;
      }

      if (!mounted) return;
      setState(() {
        _nomeUsuario = primeiroNome;
      });
    }, onError: (e) {
      debugPrint('Erro ao ouvir perfil do usuário: $e');
    });
  }

  Future<void> _monitorarGuardiao() async {
    final docUsuario = await _fs.usuario.doc(_uid).get();
    final data = docUsuario.data() as Map<String, dynamic>?;
    final guardioesList = (data?['guardioes'] as List?) ?? [];
    final bool temGuardiao = guardioesList.isNotEmpty;

    final aceitosSnap = await _fs.guardioes
        .where('id_guardiao', isEqualTo: _uid)
        .where('status', isEqualTo: 'aceito')
        .limit(1)
        .get();

    final ativosSnap = await _fs.guardioes
        .where('id_guardiao', isEqualTo: _uid)
        .where('status', isEqualTo: 'ativo')
        .limit(1)
        .get();

    final bool euGuardoAlguem =
        aceitosSnap.docs.isNotEmpty || ativosSnap.docs.isNotEmpty;

    setState(() {
      _temGuardiao = temGuardiao;
      _guardoAlguem = euGuardoAlguem;
      _carregandoRelacoes = false;
    });

    // Agora, vamos escutar em tempo real qualquer mudança nas coleções
    _fs.guardioes
        .where('id_usuario', isEqualTo: _uid)
        .where('status', isEqualTo: 'aceito')
        .snapshots()
        .listen((event) {
      _verificarStatusGuardiao();
    });

    _fs.usuario.doc(_uid).snapshots().listen((doc) {
      _verificarStatusGuardiao();
    });
  }

  // Método que verifica e atualiza o status do usuário em tempo real
  Future<void> _verificarStatusGuardiao() async {
    final docUsuario = await _fs.usuario.doc(_uid).get();
    final data = docUsuario.data() as Map<String, dynamic>?;
    final guardioesList = (data?['guardioes'] as List?) ?? [];
    final bool temGuardiao = guardioesList.isNotEmpty;

    final aceitosSnap = await _fs.guardioes
        .where('id_guardiao', isEqualTo: _uid)
        .where('status', isEqualTo: 'aceito')
        .limit(1)
        .get();

    final ativosSnap = await _fs.guardioes
        .where('id_guardiao', isEqualTo: _uid)
        .where('status', isEqualTo: 'ativo')
        .limit(1)
        .get();

    final bool euGuardoAlguem =
        aceitosSnap.docs.isNotEmpty || ativosSnap.docs.isNotEmpty;

    setState(() {
      _temGuardiao = temGuardiao;
      _guardoAlguem = euGuardoAlguem;
    });
  }

  Future<void> _solicitarPermissaoInicial() async {
    await _requestAllLocationPermissions();
  }

  /// Diálogo genérico com estilinho InTrouble
  Future<void> _showLocationDialog({
    required String title,
    required String message,
    bool showSettingsButton = false,
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Agora não'),
            ),
            if (showSettingsButton)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colD9B4BB,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _openAppSettings();
                },
                child: const Text('Abrir configurações'),
              ),
          ],
        );
      },
    );
  }

  /// Diálogo específico pro GPS desligado, com ícone e rosa
  Future<bool> _showGpsDialogInTroubleStyle() async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _colF2C4CD,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ative sua localização',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Para que o InTrouble funcione corretamente (SOS e localização em tempo real), '
            'é importante que o GPS do seu aparelho esteja ligado.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Agora não'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _colF2C4CD,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                // Usuário diz que já ligou o GPS
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Já ativei'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _requestAllLocationPermissions() async {
    try {
      // 1) GPS ligado?
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Mostra o diálogo estilizado
        final confirmou = await _showGpsDialogInTroubleStyle();

        if (!confirmou) {
          // Usuário clicou "Agora não"
          return false;
        }

        // Usuário disse que já ativou → conferimos de novo
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          // Ainda desligado → não fica insistindo
          return false;
        }
      }

      // 2) Permissão de localização em primeiro plano
      var locStatus = await ph.Permission.location.status;
      if (!locStatus.isGranted) {
        locStatus = await ph.Permission.location.request();
      }

      if (locStatus.isDenied) {
        await _showLocationDialog(
          title: 'Permissão necessária',
          message:
              'Sem a permissão de localização, não conseguimos mostrar seu ponto '
              'para os seus guardiões quando você aciona o SOS.',
        );
        return false;
      }

      if (locStatus.isPermanentlyDenied) {
        await _showLocationDialog(
          title: 'Localização bloqueada',
          message:
              'Você bloqueou a localização para o InTrouble. '
              'Para ativar novamente, abra as configurações do aplicativo.',
          showSettingsButton: true,
        );
        return false;
      }

      // 3) Localização em 2º plano (opcional, mas recomendada)
      var alwaysStatus = await ph.Permission.locationAlways.status;
      if (!alwaysStatus.isGranted) {
        alwaysStatus = await ph.Permission.locationAlways.request();
      }

      if (alwaysStatus.isDenied) {
        // Não bloqueia o app, só avisa que o rastreio contínuo pode falhar
        await _showLocationDialog(
          title: 'Rastreamento limitado',
          message:
              'Você pode usar o InTrouble, mas sem a localização em segundo plano '
              'algumas funções de acompanhamento contínuo podem não funcionar.',
        );
        return true;
      }

      if (alwaysStatus.isPermanentlyDenied) {
        await _showLocationDialog(
          title: 'Localização em 2º plano bloqueada',
          message:
              'Para que seus guardiões vejam seus movimentos mesmo com o app fechado, '
              'ative a localização em segundo plano nas configurações do aplicativo.',
          showSettingsButton: true,
        );
        // Se quiser que o app continue mesmo assim, troque para `return true;`
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao solicitar permissões: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar permissões: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      debugPrint('Erro ao abrir configurações do app: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir as configurações. Abra manualmente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TelaLogin()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao deslogar: $e')),
        );
      }
    }
  }

  // Header bonitinho com gradiente rosa
  Widget _buildHeader(User? user) {
    // Prioridade: nome do Firestore -> displayName -> parte do e-mail
    String nome = _nomeUsuario;

    if (nome.isEmpty && user != null) {
      final display = user.displayName?.trim() ?? '';
      if (display.isNotEmpty) {
        nome = display.split(RegExp(r'\s+')).first;
      } else if (user.email != null && user.email!.isNotEmpty) {
        nome = user.email!.split('@').first;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_colF2DFE0, _colF2C4CD],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bem-vindo ao InTrouble',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nome.isNotEmpty ? 'Olá, $nome 👋' : 'Olá 👋',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gerencie suas ocorrências, acompanhe quem você protege '
            'e acione o SOS quando precisar.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // Botão estilizado padrão da Home
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? background,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background ?? _colF2C4CD,
          foregroundColor: Colors.black87,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isAdmin = user?.email == adminEmail;

    return Scaffold(
      backgroundColor: _colF2F2F2,
      appBar: AppBar(
        backgroundColor: _colF2C4CD,
        elevation: 0,
        title: const Text(
          "InTrouble",
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PerfilGuardiaoScreen(),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundColor: _colF2DFE0,
                backgroundImage:
                    (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                        ? NetworkImage(user.photoURL!)
                        : null,
                child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                    ? const Icon(Icons.account_circle,
                        size: 28, color: Colors.black54)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(user),
              const SizedBox(height: 24),

              if (_carregandoRelacoes)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16.0),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

              // Card principal de ações
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isAdmin) ...[
                      const Text(
                        'Área administrativa',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.person_add_alt,
                        label: 'Cadastrar usuário',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TelaUsuario()),
                          );
                        },
                        background: _colF2DFE0,
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.list_alt,
                        label: 'Tipos de ocorrência',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TipoOcorrencia(),
                            ),
                          );
                        },
                        background: _colF2DFE0,
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.settings,
                        label: 'Configurações (Admin - E-mail)',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConfigScreen(),
                            ),
                          );
                        },
                        background: _colD9B4BB,
                      ),
                      const Divider(height: 32),
                    ],

                    const Text(
                      'Minhas ações',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vítima
                    _buildActionButton(
                      icon: Icons.flag_outlined,
                      label: 'Registrar ocorrência',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const OcorrenciaPage()),
                        );
                      },
                      background: _colF2C4C4,
                    ),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      icon: Icons.article_outlined,
                      label: 'Minhas ocorrências',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const OcorrenciasPage()),
                        );
                      },
                      background: _colF2C4CD,
                    ),
                    const SizedBox(height: 20),

                    // Guardião (eu guardo alguém)
                    if (_guardoAlguem) ...[
                      const Text(
                        'Como guardião',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.visibility_outlined,
                        label: 'Ocorrências que acompanho',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const TelaOcorrenciasAcompanhar(),
                            ),
                          );
                        },
                        background: _colF2DFE0,
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.location_on_outlined,
                        label: 'Localização da vítima',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GuardianMapPage(),
                            ),
                          );
                        },
                        background: _colF2C4CD,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // SOS -> só aparece se eu tiver pelo menos um guardião
                    if (_temGuardiao) ...[
                      const Text(
                        'Emergência',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActionButton(
                        icon: Icons.warning_amber_rounded,
                        label: 'SOS',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TelaVitimaSOS(),
                            ),
                          );
                        },
                        background: _colD9B4BB,
                      ),
                      const SizedBox(height: 20),
                    ],

                    _buildActionButton(
                      icon: Icons.logout,
                      label: 'Sair',
                      onPressed: () => _logout(context),
                      background: Colors.grey.shade300,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
