import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard copiar valores

// seus serviços
import 'package:crud/services/firestore.dart';
import 'package:crud/services/enviar_email.dart';

class PerfilGuardiaoScreen extends StatefulWidget {
  const PerfilGuardiaoScreen({Key? key}) : super(key: key);

  @override
  State<PerfilGuardiaoScreen> createState() => _PerfilGuardiaoScreenState();
}

class _PerfilGuardiaoScreenState extends State<PerfilGuardiaoScreen>
    with SingleTickerProviderStateMixin {
  // --------- Paleta ----------
  static const _colF2DFE0 = Color(0xFFF2DFE0);
  static const _colF2C4CD = Color(0xFFF2C4CD);
  static const _colD9B4BB = Color(0xFFD9B4BB);
  static const _colF2C4C4 = Color(0xFFF2C4C4);
  static const _colF2F2F2 = Color(0xFFF2F2F2);

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _colD9B4BB,
      brightness: Brightness.light,
    ).copyWith(
      primary: _colD9B4BB,
      primaryContainer: _colF2C4CD,
      secondary: _colF2C4C4,
      background: _colF2F2F2,
      surface: _colF2DFE0,
      onPrimary: Colors.white,
      onBackground: Colors.black87,
      onSurface: Colors.black87,
    );

    final base = Theme.of(context);
    final themed = base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _colF2F2F2,
      appBarTheme: const AppBarTheme(
        backgroundColor: _colD9B4BB,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: _colF2DFE0,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _colD9B4BB,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(thickness: 1),
    );

    return Theme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meu Perfil'),
          bottom: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.person_outline), text: 'Perfil'),
              Tab(icon: Icon(Icons.shield_outlined), text: 'Guardiões'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: const [
            _PerfilTab(),
            _GuardioesTab(),
          ],
        ),
      ),
    );
  }
}

/* =====================  ABA 1: PERFIL  ===================== */

class _PerfilTab extends StatefulWidget {
  const _PerfilTab();

  @override
  State<_PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<_PerfilTab> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _cpf = TextEditingController();
  final _tel = TextEditingController();
  final _nasc = TextEditingController();
  String? _sexo;

  bool _loading = true;
  String? _err;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      if (_user == null) throw 'Usuário não autenticado.';
      final doc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(_user!.uid)
          .get();

      if (!doc.exists) throw 'Cadastro não encontrado.';

      final data = doc.data() as Map<String, dynamic>;
      _nome.text = (data['nome'] ?? '').toString().trim();
      _email.text = (data['email'] ?? _user?.email ?? '').toString().trim();
      _cpf.text = _maskCPF((data['cpf'] ?? '').toString());
      _tel.text = _maskPhone((data['numerotelefone'] ?? '').toString());
      final dn = data['dataNasc'];
      if (dn is Timestamp) {
        _nasc.text = _fmtDate(dn.toDate());
      } else if (dn is String && dn.isNotEmpty) {
        _nasc.text = _normalizeDateString(dn);
      }
      _sexo = data['sexo']?.toString();
    } catch (e) {
      _err = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _maskCPF(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return raw;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  String _maskPhone(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7, 11)}';
    } else if (d.length >= 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6, 10)}';
    }
    return raw;
  }

  String _unmaskPhone(String s) {
    return s.replaceAll(RegExp(r'\D'), '');
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _normalizeDateString(String s) {
    final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (iso.hasMatch(s)) {
      final p = s.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return s;
  }

  Future<void> _editarTelefone() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    // Usa o telefone atual já formatado com máscara
    final controller = TextEditingController(
      text: _maskPhone(_unmaskPhone(_tel.text)),
    );

    String? erroLocal;

    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Editar telefone'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      _TelefoneInputFormatter(), // máscara (DD) XXXXX-XXXX
                    ],
                    decoration: InputDecoration(
                      labelText: 'Telefone com DDD',
                      hintText: '(61) 99999-9999',
                      errorText: erroLocal,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    final raw = controller.text.trim();
                    final digits =
                        raw.replaceAll(RegExp(r'\D'), ''); // só números

                    if (digits.length < 10 || digits.length > 11) {
                      setStateDialog(() {
                        erroLocal =
                            'Informe um telefone válido (10 ou 11 dígitos).';
                      });
                      return;
                    }

                    Navigator.pop(ctx, digits);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado == null) return; // usuário cancelou

    final digits = resultado;

    try {
      await FirebaseFirestore.instance
          .collection('usuario')
          .doc(_user!.uid)
          .update({'numerotelefone': digits});

      setState(() {
        _tel.text = _maskPhone(digits);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefone atualizado com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar telefone: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoURL = FirebaseAuth.instance.currentUser?.photoURL;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 44, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_err!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              )
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho com avatar
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _PerfilGuardiaoScreenState._colF2C4CD,
                  _PerfilGuardiaoScreenState._colD9B4BB
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                      ? NetworkImage(photoURL)
                      : null,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: (photoURL == null || photoURL.isEmpty)
                      ? const Icon(Icons.person, size: 40, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _HeaderBadge(name: _nome.text, email: _email.text),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dados básicos
          _SectionCard(
            title: 'Dados básicos',
            accent: _PerfilGuardiaoScreenState._colD9B4BB,
            children: [
              _InfoTile(
                icon: Icons.badge_outlined,
                label: 'Nome',
                value: _nome.text.isEmpty ? '—' : _nome.text,
                accent: _PerfilGuardiaoScreenState._colD9B4BB,
              ),
              _InfoTile(
                icon: Icons.alternate_email,
                label: 'E-mail',
                value: _email.text.isEmpty ? '—' : _email.text,
                copyable: true,
                accent: _PerfilGuardiaoScreenState._colD9B4BB,
              ),
              _InfoTile(
                icon: Icons.perm_identity,
                label: 'CPF',
                value: _cpf.text.isEmpty ? '—' : _cpf.text,
                copyable: true,
                accent: _PerfilGuardiaoScreenState._colD9B4BB,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contato + botão editar telefone
          _SectionCard(
            title: 'Contato',
            accent: _PerfilGuardiaoScreenState._colF2C4C4,
            children: [
              _InfoTile(
                icon: Icons.phone_iphone,
                label: 'Telefone',
                value: _tel.text.isEmpty ? '—' : _tel.text,
                copyable: true,
                accent: _PerfilGuardiaoScreenState._colF2C4C4,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _editarTelefone,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Editar telefone'),
                  style: TextButton.styleFrom(
                    foregroundColor: _PerfilGuardiaoScreenState._colF2C4C4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Outros
          _SectionCard(
            title: 'Outros',
            accent: _PerfilGuardiaoScreenState._colF2C4CD,
            children: [
              _InfoTile(
                icon: Icons.event,
                label: 'Data de Nascimento',
                value: _nasc.text.isEmpty ? '—' : _nasc.text,
                accent: _PerfilGuardiaoScreenState._colF2C4CD,
              ),
              _InfoTile(
                icon: Icons.wc_outlined,
                label: 'Sexo',
                value: _sexo ?? '—',
                accent: _PerfilGuardiaoScreenState._colF2C4CD,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Mantém apenas dígitos
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limita a 11 dígitos (DDD + número)
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    String formatted;

    if (digits.isEmpty) {
      formatted = '';
    } else if (digits.length <= 2) {
      // (DD
      formatted = '(${digits}';
    } else if (digits.length <= 6) {
      // (DD) XXXX ou (DD) XXXXX (sem traço ainda)
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else {
      if (digits.length == 10) {
        // (DD) XXXX-XXXX
        formatted =
            '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
      } else {
        // 11 dígitos: (DD) XXXXX-XXXX
        formatted =
            '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}



/* =====================  ABA 2: GUARDIÕES  ===================== */

class _GuardioesTab extends StatefulWidget {
  const _GuardioesTab();

  @override
  State<_GuardioesTab> createState() => _GuardioesTabState();
}

class _GuardioesTabState extends State<_GuardioesTab> {
  final FirestoreService _service = FirestoreService();
  final EmailBackendService _emailSvc = EmailBackendService();
  final String _meuId = FirebaseAuth.instance.currentUser!.uid;
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _tplConvite() async {
    final snap = await FirebaseFirestore.instance
        .collection('textoEmails')
        .doc('convite_guardião')
        .get();

    if (!snap.exists) {
      return {
        'assunto': 'Convite para ser Guardião',
        'body': 'Olá {nomeGuardiao}, {nome} convidou você para ser guardião.',
        'htmlBody':
            '<p>Olá {nomeGuardiao}, <b>{nome}</b> convidou você para ser guardião.</p>',
      };
    }

    final data = (snap.data() ?? {}) as Map<String, dynamic>;
    return {
      'assunto': (data['assunto'] ?? 'Convite para ser Guardião').toString(),
      'body': (data['body'] ?? data['texto'] ?? '').toString(),
      'htmlBody': (data['html'] ?? '').toString(),
    };
  }

  Future<void> _enviarConvite() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o e-mail do guardião.')),
      );
      return;
    }
    try {
      await _service.convidarGuardiaoPorEmail(email, _meuId);

      // Dispara email (se tiver backend configurado)
      try {
        final tpl = await _tplConvite();
        await _emailSvc.enviarEmailViaBackend(
          to: email,
          subject: tpl['assunto'] ?? 'Convite para ser Guardião',
          body: tpl['body']?.isNotEmpty == true
              ? tpl['body']!
              : 'Olá {nomeGuardiao}, {nome} convidou você para ser guardião.',
          htmlBody:
              (tpl['htmlBody']?.isNotEmpty == true) ? tpl['htmlBody'] : null,
          nomeGuardiao: null,
          textoSocorro: null,
        );
      } catch (_) {
        // Ignora falha de email para não quebrar UX do convite
      }

      _emailCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite enviado!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar convite: $e')),
      );
    }
  }

  Future<void> _aceitarConvite(String conviteId, String idUsuario) async {
    try {
      await _service.aceitarConviteGuardiao(conviteId, idUsuario, _meuId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite aceito com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aceitar: $e')),
      );
    }
  }

  Future<void> _recusarConvite(String conviteId) async {
    try {
      await _service.recusarConviteGuardiao(conviteId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite recusado.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao recusar: $e')),
      );
    }
  }

  // Função para inativar o guardião
  void _inativarGuardiao(String idGuardiao) async {
    try {
      await _service.inativarGuardiao(_meuId, idGuardiao); // Chama a função de inativação
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardião inativado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao inativar guardião: $e')),
      );
    }
  }

  // Função para reativar o guardião
  void _reativarGuardiao(String idGuardiao) async {
    try {
      await _service.reativarGuardiao(_meuId, idGuardiao); // Chama a função de reativação
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardião reativado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao reativar guardião: $e')),
      );
    }
  }

  Stream<QuerySnapshot> get _convitesPendentesStream =>
      _service.getConvitesRecebidosGuardiao(_meuId);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Enviar Convite
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(
                    title: 'Enviar Convite',
                    color: _PerfilGuardiaoScreenState._colD9B4BB,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-mail do Guardião',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _enviarConvite,
                      icon: const Icon(Icons.send),
                      label: const Text('Enviar Convite'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Convites Recebidos
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardHeader(
                    title: 'Convites Recebidos',
                    color: _PerfilGuardiaoScreenState._colF2C4CD,
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: _convitesPendentesStream,
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final convites = snap.data?.docs ?? [];
                      if (convites.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Nenhum convite pendente.'),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: convites.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (ctx2, i) {
                          final doc = convites[i];
                          final conviteId = doc.id;
                          final nomeUsuario =
                              (doc['nome_usuario'] as String?) ?? '';
                          final idUsuario = doc['id_usuario'] as String;
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.mail_outline)),
                            title: Text(nomeUsuario.isEmpty
                                ? 'Convite recebido'
                                : 'Convite de: $nomeUsuario'),
                            subtitle: Text('Status: ${doc['status']}'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  tooltip: 'Aceitar',
                                  onPressed: () =>
                                      _aceitarConvite(conviteId, idUsuario),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  tooltip: 'Recusar',
                                  onPressed: () =>
                                      _recusarConvite(conviteId),
                                ),
                                // Exibir o ícone de inativação (lixeira) ou reativação
                                if (doc['status'] != 'inativo')
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    tooltip: 'Inativar',
                                    onPressed: () =>
                                        _inativarGuardiao(doc['id_guardiao']),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.refresh,
                                        color: Colors.green),
                                    tooltip: 'Reativar',
                                    onPressed: () =>
                                        _reativarGuardiao(doc['id_guardiao']),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Meus Guardiões (ativos + inativados para reativar)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _CardHeader(
                    title: 'Meus Guardiões',
                    color: _PerfilGuardiaoScreenState._colF2C4C4,
                  ),
                  SizedBox(height: 8),
                  _MeusGuardioesSection(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Usuários que eu guardo
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _CardHeader(
                    title: 'Usuários que eu guardo',
                    color: _PerfilGuardiaoScreenState._colF2DFE0,
                  ),
                  SizedBox(height: 8),
                  _UsuariosQueGuardoSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



/* ------------------ Sub-seções reutilizáveis ------------------ */

class _MeusGuardioesSection extends StatelessWidget {
  const _MeusGuardioesSection();

  @override
  Widget build(BuildContext context) {
    final String meuId = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('usuario').doc(meuId).get(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
        }
        final userDoc = snap.data;
        if (userDoc == null || !userDoc.exists) {
          return const Text('Nenhum guardião cadastrado.');
        }
        final data = userDoc.data()! as Map<String, dynamic>;
        final List<String> ativos = List<String>.from(data['guardioes'] ?? []);

        // Ativos
        final ativosList = ativos.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum guardião ativo.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ativos.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx2, i) {
                  final gid = ativos[i];
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('usuario')
                        .doc(gid)
                        .get(),
                    builder: (c2, s2) {
                      if (s2.connectionState == ConnectionState.waiting) {
                        return const ListTile(title: Text('Carregando...'));
                      }
                      if (s2.data == null || !s2.data!.exists) {
                        return const ListTile(
                            title: Text('Guardião não encontrado'));
                      }
                      final g = s2.data!.data()! as Map<String, dynamic>;
                      return ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.shield)),
                        title: Text(g['nome'] ?? 'Sem nome'),
                        subtitle: Text(g['email'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Inativar guardião',
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('usuario')
                                .doc(meuId)
                                .update({
                              'guardioes': FieldValue.arrayRemove([gid])
                            });
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('Guardião inativado')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [ativosList],
        );
      },
    );
  }
}

class _UsuariosQueGuardoSection extends StatelessWidget {
  const _UsuariosQueGuardoSection();

  @override
  Widget build(BuildContext context) {
    final String meuId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guardiões')
          .where('id_guardiao', isEqualTo: meuId)
          .where('status', isEqualTo: 'aceito')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('Você não guarda nenhum usuário.');
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (ctx2, i) {
            final doc = docs[i];
            final idUsuario = doc['id_usuario'] as String;
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('usuario')
                  .doc(idUsuario)
                  .get(),
              builder: (c3, s3) {
                if (s3.connectionState == ConnectionState.waiting) {
                  return const ListTile(title: Text('Carregando...'));
                }
                if (s3.data == null || !s3.data!.exists) {
                  return const ListTile(title: Text('Usuário não encontrado'));
                }
                final u = s3.data!.data()! as Map<String, dynamic>;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(u['nome'] ?? 'Sem nome'),
                  subtitle: Text(u['email'] ?? ''),
                );
              },
            );
          },
        );
      },
    );
  }
}

/* ------------------ Widgets utilitários ------------------ */

class _HeaderBadge extends StatelessWidget {
  final String name;
  final String email;
  const _HeaderBadge({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (name.isEmpty ? '—' : name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(offset: Offset(0, 1), blurRadius: 2)],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mail, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                email.isEmpty ? '—' : email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _CardHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color accent;
  const _SectionCard({required this.title, required this.children, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 20,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;
  final Color accent;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: accent.withOpacity(0.18),
        child: Icon(icon, color: accent),
      ),
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: Text(
        value.isEmpty ? '—' : value,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: copyable && value.isNotEmpty && value != '—'
          ? IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy_all_rounded),
              color: accent,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copiado!')),
                  );
                }
              },
            )
          : null,
    );
  }
}