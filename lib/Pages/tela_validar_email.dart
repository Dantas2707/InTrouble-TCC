import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// importe a tela de login:
import 'tela_login.dart'; // ajuste o caminho se estiver em outra pasta

class TelaValidarEmail extends StatefulWidget {
  const TelaValidarEmail({Key? key}) : super(key: key);

  @override
  _TelaValidarEmailState createState() => _TelaValidarEmailState();
}

class _TelaValidarEmailState extends State<TelaValidarEmail> {
  final _formKey = GlobalKey<FormState>();
  final tokenController = TextEditingController();
  bool _isLoading = false;

  // Função para validar o token e marcar o e-mail como verificado
  Future<void> validarEmail() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final token = tokenController.text.trim();

        // Chama o backend para validar o token
        final response = await http.post(
          Uri.parse('https://troca-senha-e-validar-email.onrender.com/auth/verify-email'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'token': token}),
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('E-mail verificado com sucesso!')),
          );

          // 👉 Navegação direta para a tela de login, sem usar rota nomeada
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const TelaLogin(),
            ),
          );
        } else {
          throw Exception('Erro ao validar o e-mail.');
        }
      } catch (error) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${error.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
     return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Validar E-mail'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Insira o token de verificação',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Token é obrigatório';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: validarEmail,
                        child: const Text('Validar E-mail'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}