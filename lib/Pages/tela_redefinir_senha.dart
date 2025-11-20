import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Paleta
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kRosaClaro = Color(0xFFF2C4CD);      // #F2C4CD
const kRosaMedio = Color(0xFFD9B4BB);      // #D9B4BB
const kRosaSuave = Color(0xFFF2C4C4);      // #F2C4C4
const kCinzaClaro = Color(0xFFF2F2F2);     // #F2F2F2

class RedefinirSenhaPage extends StatefulWidget {
  const RedefinirSenhaPage({Key? key}) : super(key: key);

  @override
  State<RedefinirSenhaPage> createState() => _RedefinirSenhaPageState();
}

class _RedefinirSenhaPageState extends State<RedefinirSenhaPage> {
  final _emailCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _emailEnviado = false;
  bool _tokenValido = false;
  String? _mensagemErro;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  // ================= LÓGICA =================

  // Passo 1: Enviar e-mail com token
  Future<void> _enviarEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _mensagemErro = 'Informe seu e-mail.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://troca-senha-e-validar-email.onrender.com/auth/request-reset',
        ),
        body: json.encode({'email': email}),
        headers: {'Content-Type': 'application/json'},
      );

      final responseData = json.decode(response.body);

      if (response.statusCode != 200) {
        setState(() => _mensagemErro =
            responseData['error'] ?? 'Erro ao enviar e-mail.');
        return;
      }

      setState(() {
        _emailEnviado = true;
        _mensagemErro = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token enviado para o e-mail.')),
        );
      }
    } catch (e) {
      setState(() => _mensagemErro = 'Erro ao enviar e-mail: $e');
    }
  }

  // Passo 2: Validar token (usando email + token, como no primeiro código)
  Future<void> _validarToken() async {
    final token = _tokenCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => _mensagemErro = 'Informe seu e-mail.');
      return;
    }

    if (token.isEmpty) {
      setState(() => _mensagemErro = 'Informe o token recebido.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://troca-senha-e-validar-email.onrender.com/auth/verify-token',
        ),
        body: json.encode({'token': token, 'email': email}),
        headers: {'Content-Type': 'application/json'},
      );

      final responseData = json.decode(response.body);

      if (response.statusCode != 200) {
        setState(() {
          _mensagemErro =
              responseData['error'] ?? 'Erro ao validar token.';
          _tokenValido = false;
        });
        return;
      }

      if (responseData['ok'] == true) {
        setState(() {
          _mensagemErro = null;
          _tokenValido = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['message'] ?? 'Token validado com sucesso.',
              ),
            ),
          );
        }
      } else {
        setState(() {
          _mensagemErro =
              responseData['error'] ?? 'Token inválido ou expirado.';
          _tokenValido = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = 'Erro ao validar token: $e';
        _tokenValido = false;
      });
    }
  }

  // Passo 3: Alterar senha
  Future<void> _alterarSenha() async {
    if (_senhaCtrl.text != _confirmarCtrl.text) {
      setState(() => _mensagemErro = 'As senhas não coincidem.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://troca-senha-e-validar-email.onrender.com/auth/reset-password',
        ),
        body: json.encode({
          'token': _tokenCtrl.text.trim(),
          'newPassword': _senhaCtrl.text,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _mensagemErro = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['message'] ?? 'Senha redefinida com sucesso!',
              ),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        setState(() {
          _mensagemErro =
              responseData['error'] ?? 'Erro ao redefinir a senha.';
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = 'Erro ao redefinir a senha: $e';
      });
    }
  }

  // ================= WIDGETS AUXILIARES =================

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
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
        fontSize: 14,
      ),
    );
  }

  Widget _buildStepIndicator() {
    // 3 etapas: 1) e-mail, 2) token, 3) nova senha
    int activeIndex;
    if (!_emailEnviado) {
      activeIndex = 0;
    } else if (_emailEnviado && !_tokenValido) {
      activeIndex = 1;
    } else {
      activeIndex = 2;
    }

    final titles = ['E-mail', 'Token', 'Nova senha'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(3, (i) {
        final active = i == activeIndex;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 6,
                margin: EdgeInsets.only(
                  left: i == 0 ? 0 : 4,
                  right: i == 2 ? 0 : 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: active ? kRosaMedio : kRosaMuitoClaro,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titles[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: const Color.fromARGB(255, 90, 70, 76),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar com o rosa da paleta
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kRosaClaro,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Redefinir senha',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Fundo em degradê suave
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
                constraints: const BoxConstraints(maxWidth: 450),
                child: Card(
                  color: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Esqueceu a senha?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color.fromARGB(255, 82, 60, 66),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Vamos te ajudar a criar uma nova senha em três passos: '
                          'enviar e-mail, validar o token e cadastrar a nova senha.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color.fromARGB(255, 110, 90, 96),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStepIndicator(),
                        const SizedBox(height: 16),

                        if (_mensagemErro != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _mensagemErro!,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (!_emailEnviado) ...[
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _decoration('E-mail cadastrado'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _enviarEmail,
                            style: _buttonStyle(),
                            child: const Text('Enviar e-mail com token'),
                          ),
                        ],

                        if (_emailEnviado && !_tokenValido) ...[
                          TextField(
                            controller: _tokenCtrl,
                            decoration:
                                _decoration('Token recebido no e-mail'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _validarToken,
                            style: _buttonStyle(),
                            child: const Text('Validar token'),
                          ),
                        ],

                        if (_tokenValido) ...[
                          TextField(
                            controller: _senhaCtrl,
                            obscureText: true,
                            decoration: _decoration('Nova senha'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmarCtrl,
                            obscureText: true,
                            decoration: _decoration('Confirmar nova senha'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _alterarSenha,
                            style: _buttonStyle(),
                            child: const Text('Redefinir senha'),
                          ),
                        ],
                      ],
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
