import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 pra usar TextInputFormatter
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crud/services/firestore.dart';
import 'tela_login.dart';
import 'tela_validar_email.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// ===================== PALETA =====================
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kRosaClaro      = Color(0xFFF2C4CD); // #F2C4CD
const kRosaMedio      = Color(0xFFD9B4BB); // #D9B4BB
const kRosaSuave      = Color(0xFFF2C4C4); // #F2C4C4
const kCinzaClaro     = Color(0xFFF2F2F2); // #F2F2F2

// ===================== MENSAGENS / EMAIL (opcional) =====================

Future<String?> buscarMensagemPorCampo(String chave) async {
  final qs = await FirebaseFirestore.instance
      .collection('mensagens')
      .where('chave', isEqualTo: chave)
      .limit(1)
      .get();
  if (qs.docs.isEmpty) return null;
  final data = qs.docs.first.data();
  return (data['conteudo'] as String?)?.trim();
}

/// Substitui variáveis estilo {{nome}} no template
String preencherVariaveisMensagem(String template, Map<String, String> vars) {
  var out = template;
  vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
  return out;
}

/// Stub para envio de email via backend (se quiser usar templates depois)
Future<void> enviarEmailViaBackend({
  required String to,
  required String subject,
  required String body,
}) async {
  // TODO: implemente chamada HTTP/Cloud Function aqui, se quiser reaproveitar templates.
}

// ===================== TELA USUÁRIO (CADASTRO) =====================

class TelaUsuario extends StatefulWidget {
  const TelaUsuario({Key? key}) : super(key: key);

  @override
  State<TelaUsuario> createState() => _TelaUsuarioState();
}

class _TelaUsuarioState extends State<TelaUsuario> {
  final FirestoreService firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();

  final nomeController = TextEditingController();
  final emailController = TextEditingController();
  final telefoneController = TextEditingController();
  final dataNascController = TextEditingController();
  final senhaController = TextEditingController();
  final senhaConfirmController = TextEditingController();

  String? _sexoSelecionado;
  bool _isLoading = false;

  // 👇 Flags para mostrar/ocultar as senhas
  bool _senhaVisivel = false;
  bool _senhaConfirmVisivel = false;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.setLanguageCode('pt');
  }

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    telefoneController.dispose();
    dataNascController.dispose();
    senhaController.dispose();
    senhaConfirmController.dispose();
    super.dispose();
  }

  bool validarEmail(String email) {
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
    return regex.hasMatch(email);
  }

  String gerarHashSenha(String senha) {
    final bytes = utf8.encode(senha);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  Future<void> selecionarDataNascimento(BuildContext context) async {
    final hoje = DateTime.now();

    final dataEscolhida = await showDatePicker(
      context: context,
      initialDate: DateTime(hoje.year - 20),
      firstDate: DateTime(hoje.year - 120),
      lastDate: DateTime(hoje.year - 13),
      locale: const Locale('pt', 'BR'),
      helpText: 'Selecione a data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'OK',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kRosaClaro,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: kRosaClaro,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataEscolhida != null) {
      setState(() {
        dataNascController.text =
            DateFormat('dd/MM/yyyy', 'pt_BR').format(dataEscolhida);
      });
    }
  }

  Future<void> registrarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    if (senhaController.text != senhaConfirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dataNasc = DateFormat('dd/MM/yyyy', 'pt_BR')
          .parseStrict(dataNascController.text.trim());

      final hashSenha = gerarHashSenha(senhaController.text.trim());

      // 👇 só dígitos do telefone para salvar no Firestore
      final telefoneDigits =
          telefoneController.text.replaceAll(RegExp(r'\D'), '');

      final authResult = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: senhaController.text.trim(),
      );
      final uid = authResult.user!.uid;

      // Email de verificação padrão do Firebase
      await authResult.user!.sendEmailVerification();

      // Dados do usuário no Firestore (via seu service)
      final dadosUsuario = {
        'nome': nomeController.text.trim(),
        'email': emailController.text.trim(),
        'numerotelefone': telefoneDigits, // 👈 só números
        'dataNasc': dataNasc,
        'sexo': _sexoSelecionado,
        'inativar': false,
        'timestamp': DateTime.now(),
        'senha': hashSenha, // hash da senha
      };

      await firestoreService.addUsuario(uid, dadosUsuario);

      // ========= INTEGRAÇÃO COM BACKEND DE VERIFICAÇÃO POR TOKEN =========
      final response = await http.post(
        Uri.parse(
            'https://troca-senha-e-validar-email.onrender.com/auth/request-verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': emailController.text.trim()}),
      );

      if (response.statusCode != 200) {
        throw Exception('Erro ao enviar e-mail de verificação.');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário registrado. Verifique seu e-mail.'),
        ),
      );

      // Limpa o formulário
      _formKey.currentState!.reset();
      setState(() {
        _sexoSelecionado = null;
        dataNascController.clear();
        senhaController.clear();
        senhaConfirmController.clear();
        telefoneController.clear();
        _isLoading = false;
      });

      // Vai para a tela de validação de e-mail (token)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const TelaValidarEmail(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // ===================== ESTILO =====================

  InputDecoration _decoration(
    String label, {
    IconData? icon,
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: icon != null
          ? Icon(icon, color: const Color.fromARGB(255, 120, 96, 102))
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: kCinzaClaro,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kRosaClaro, width: 1.4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: kRosaClaro,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar com a paleta rosa
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kRosaClaro,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Criar conta",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Fundo com gradiente
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  color: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Bem-vinda(o) ao InTrouble',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color.fromARGB(255, 82, 60, 66),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Preencha seus dados para criar sua conta com segurança.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color.fromARGB(255, 110, 90, 96),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Nome
                          TextFormField(
                            controller: nomeController,
                            decoration:
                                _decoration('Nome completo', icon: Icons.person),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Nome é obrigatório.';
                              }
                              final nome = value.trim();
                              if (!RegExp(r'^[A-Za-zÀ-ÿ\s]+$').hasMatch(nome)) {
                                return 'Nome deve conter apenas letras e espaços.';
                              }
                              if (nome.length < 5 || nome.length > 100) {
                                return 'Nome deve ter entre 5 e 100 caracteres.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // E-mail
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _decoration(
                              'E-mail',
                              icon: Icons.email_outlined,
                            ),
                            validator: (value) =>
                                value == null || !validarEmail(value)
                                    ? 'E-mail inválido.'
                                    : null,
                          ),
                          const SizedBox(height: 12),

                          // Senha
                          TextFormField(
                            controller: senhaController,
                            decoration: _decoration(
                              'Senha',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _senhaVisivel
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color.fromARGB(
                                      255, 120, 96, 102),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _senhaVisivel = !_senhaVisivel;
                                  });
                                },
                              ),
                            ),
                            obscureText: !_senhaVisivel,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Senha é obrigatória.';
                              }
                              if (value.trim().length < 6) {
                                return 'Senha deve ter no mínimo 6 caracteres.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Confirmar Senha
                          TextFormField(
                            controller: senhaConfirmController,
                            decoration: _decoration(
                              'Confirmar senha',
                              icon: Icons.lock_reset_outlined,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _senhaConfirmVisivel
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color.fromARGB(
                                      255, 120, 96, 102),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _senhaConfirmVisivel =
                                        !_senhaConfirmVisivel;
                                  });
                                },
                              ),
                            ),
                            obscureText: !_senhaConfirmVisivel,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Por favor, confirme a senha.';
                              }
                              if (value != senhaController.text) {
                                return 'As senhas não coincidem.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Telefone com máscara igual à tela de perfil
                          TextFormField(
                            controller: telefoneController,
                            decoration: _decoration(
                              'Telefone com DDD',
                              icon: Icons.phone_outlined,
                              hintText: '(61) 99999-9999',
                            ),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              _TelefoneInputFormatter(), // 👈 mesma máscara
                            ],
                            validator: (value) {
                              final txt = value?.trim() ?? '';
                              if (txt.isEmpty) {
                                return 'Telefone é obrigatório.';
                              }
                              final digits =
                                  txt.replaceAll(RegExp(r'\D'), '');
                              if (digits.length < 10 || digits.length > 11) {
                                return 'Informe um telefone válido com DDD (10 ou 11 dígitos).';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Data de Nascimento
                          TextFormField(
                            controller: dataNascController,
                            readOnly: true,
                            decoration: _decoration(
                              'Data de nascimento',
                              icon: Icons.cake_outlined,
                            ),
                            onTap: () => selecionarDataNascimento(context),
                            validator: (value) {
                              final txt = value?.trim() ?? '';
                              if (txt.isEmpty) {
                                return 'Selecione uma data válida.';
                              }
                              try {
                                DateFormat('dd/MM/yyyy', 'pt_BR')
                                    .parseStrict(txt);
                                return null;
                              } catch (_) {
                                return 'Use o formato dd/MM/yyyy.';
                              }
                            },
                          ),
                          const SizedBox(height: 12),

                          // Sexo
                          DropdownButtonFormField<String>(
                            value: _sexoSelecionado,
                            decoration: _decoration('Sexo'),
                            items: const [
                              DropdownMenuItem(
                                value: 'Masculino',
                                child: Text('Masculino'),
                              ),
                              DropdownMenuItem(
                                value: 'Feminino',
                                child: Text('Feminino'),
                              ),
                            ],
                            onChanged: (valor) =>
                                setState(() => _sexoSelecionado = valor),
                            validator: (value) =>
                                value == null ? 'Selecione o sexo.' : null,
                          ),
                          const SizedBox(height: 20),

                          // Botão Registrar
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => registrarUsuario(),
                              style: _buttonStyle(),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text('Criar conta'),
                            ),
                          ),

                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TelaLogin(),
                                ),
                              );
                            },
                            child: const Text(
                              'Já tem conta? Fazer login',
                              style: TextStyle(
                                color: Color.fromARGB(255, 120, 96, 102),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mesmo formatter de telefone usado na tela de perfil
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
