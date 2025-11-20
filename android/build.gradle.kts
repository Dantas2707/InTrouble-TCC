import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crud/services/firestore.dart'; // <- usa as coleções já definidas
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

  // Controles dos botões
  bool _temGuardiao = false;     // tenho alguém me guardando
  bool _guardoAlguem = false;    // eu guardo alguém
  bool _carregandoRelacoes = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _solicitarPermissaoInicial();
    });
    _carregarRelacoesGuardiao();
  }

  /// Carrega:
  /// - se o usuário TEM guardião (campo `guardioes` no doc de usuario).
  /// - se o usuário GUARDA alguém (coleção `guardiões`, onde ele é `id_guardiao`).
  Future<void> _carregarRelacoesGuardiao() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _temGuardiao = false;
        _guardoAlguem = false;
        _carregandoRelacoes = false;
      });
      return;
    }

    try {
      // ---------- Tenho guardiões? (sou vítima de alguém) ----------
      final docUsuario = await _fs.usuario.doc(user.uid).get();
      final data = docUsuario.data() as Map<String, dynamic>?;
      final List guardioesList = (data?['guardioes'] as List?) ?? [];

      final bool tenhoGuardiao = guardioesList.isNotEmpty;

      // ---------- Eu guardo alguém? (sou guardião) ----------
      // procura docs em `guardiões` onde eu sou o guardião com status aceito/ativo
      final aceitosSnap = await _fs.guardioes
          .where('id_guardiao', isEqualTo: user.uid)
          .where('status', isEqualTo: 'aceito')
          .limit(1)
          .get();

      final ativosSnap = await _fs.guardioes
          .where('id_guardiao', isEqualTo: user.uid)
          .where('status', isEqualTo: 'ativo')
          .limit(1)
          .get();

      final bool euGuardoAlguem =
          aceitosSnap.docs.isNotEmpty || ativosSnap.docs.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _temGuardiao = tenhoGuardiao;
        _guardoAlguem = euGuardoAlguem;
        _carregandoRelacoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar relações de guardião: $e');
      if (!mounted) return;
      setState(() {
        _temGuardiao = false;
        _guardoAlguem = false;
        _carregandoRelacoes = false;
      });
    }
  }

  Future<void> _solicitarPermissaoInicial() async {
    final ok = await _requestAllLocationPermissions();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permissão de localização necessária para funcionar plenamente.',
          ),
        ),
      );
    }
  }

  Future<bool> _requestAllLocationPermissions() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ative o GPS para melhorar a precisão.'),
            ),
          );
        }
        return false;
      }

      final locStatus = await ph.Permission.location.status;
      ph.PermissionStatus locRequestStatus = locStatus;
      if (!locStatus.isGranted) {
        locRequestStatus = await ph.Permission.location.request();
      }

      if (locRequestStatus.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão de localização negada.'),
            ),
          );
        }
        return false;
      }

      if (locRequestStatus.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permissão de localização negada permanentemente. Abra as configurações.',
              ),
            ),
          );
        }
        await _openAppSettings();
        return false;
      }

      final alwaysStatus = await ph.Permission.locationAlways.status;
      if (!alwaysStatus.isGranted) {
        final alwaysRequest = await ph.Permission.locationAlways.request();
        if (alwaysRequest.isDenied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sem localização em 2º plano. Algumas funções podem não funcionar.',
              ),
            ),
          );
        } else if (alwaysRequest.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Localização em 2º plano negada permanentemente. Abra as configurações.',
                ),
              ),
            );
          }
          await _openAppSettings();
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao solicitar permissões: $e');
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
            content:
                Text('Não foi possível abrir as configurações. Abra manualmente.'),
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
        MaterialPageRoute(builder: (context) => TelaLogin()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao deslogar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isAdmin = user?.email == adminEmail;

    return Scaffold(
      appBar: AppBar(
        title: const Text("InTrouble"),
        actions: [
          // Ícone/Avatar de usuário -> abre informações pessoais
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
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withOpacity(0.12),
                backgroundImage: (user?.photoURL != null &&
                        user!.photoURL!.isNotEmpty)
                    ? NetworkImage(user.photoURL!)
                    : null,
                child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                    ? const Icon(Icons.account_circle, size: 28)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isAdmin) ...[
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TelaUsuario()),
                    );
                  },
                  child: const Text('Cadastrar Usuário'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TipoOcorrencia()),
                    );
                  },
                  child: const Text('Ir para Tela Tipo Ocorrência'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ConfigScreen()),
                    );
                  },
                  child: const Text('Configurações (Admin - E-mail)'),
                ),
                const SizedBox(height: 20),
              ],

              // Vítima
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OcorrenciaPage()),
                  );
                },
                child: const Text('Registrar Ocorrência'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OcorrenciasPage()),
                  );
                },
                child: const Text('Minhas ocorrências'),
              ),
              const SizedBox(height: 20),

              // Guardião acompanhando vítimas -> só aparece se eu guardar alguém
              if (_guardoAlguem) ...[
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TelaOcorrenciasAcompanhar(),
                      ),
                    );
                  },
                  child: const Text('Ocorrências que acompanho'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GuardianMapPage()),
                    );
                  },
                  child: const Text('Localização da vítima'),
                ),
                const SizedBox(height: 20),
              ],

              // SOS -> só aparece se eu tiver pelo menos um guardião
              if (_temGuardiao) ...[
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TelaVitimaSOS()),
                    );
                  },
                  child: const Text('SOS'),
                ),
                const SizedBox(height: 20),
              ] else if (!_carregandoRelacoes) ...[
                const Text(
                  'Cadastre um guardião para ativar o botão SOS.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],

              ElevatedButton(
                onPressed: () => _logout(context),
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

