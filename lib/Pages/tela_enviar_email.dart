import 'package:flutter/material.dart';
import '../services/enviar_email.dart' as es;
import '../services/firestore.dart' as fs;

class EnviarEmailPage extends StatefulWidget {
  const EnviarEmailPage({Key? key}) : super(key: key);

  @override
  State<EnviarEmailPage> createState() => _EnviarEmailPageState();
}

class _EnviarEmailPageState extends State<EnviarEmailPage> {
  final _toCtrl = TextEditingController(); // Controle para o e-mail de destino
  final _subjCtrl = TextEditingController(); // Controle para o assunto
  final _bodyCtrl =
      TextEditingController(); // Controle para o corpo da mensagem
  bool _sending = false; // Flag para indicar se está enviando
  String? _selectedMessage; // Armazena o texto da mensagem selecionada

  late fs.FirestoreService
      _firestoreService; // Usando FirestoreService com o prefixo 'fs'
  List<String> _textosEmails = []; // Lista de textos de e-mails

  @override
  void initState() {
    super.initState();
    _firestoreService = fs
        .FirestoreService(); // Usando o serviço FirestoreService do firestore.dart com o prefixo 'fs'
    _loadTextosEmails();
  }

  // Carregar os textos de e-mails ativos
  Future<void> _loadTextosEmails() async {
    final textos = await _firestoreService
        .listarNomesTextosEmails(); // Corrigindo o uso do método
    setState(() {
      _textosEmails = textos;
    });
  }

  Future<void> _onMessageSelected(String? messageName) async {
    if (messageName == null) return;

    final doc = await _firestoreService.buscarTextoEmail(messageName);
    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Texto de e-mail não encontrado ou inativo.')),
      );
      return;
    }

    // Cast seguro do data
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final assunto = (data['assunto'] as String?)?.trim().isNotEmpty == true
        ? (data['assunto'] as String).trim()
        : (data['nome'] as String?)?.trim() ?? ''; // fallback para nome

    final corpo = (data['textoEmail'] as String?)?.trim().isNotEmpty == true
        ? (data['textoEmail'] as String).trim()
        : ((data['corpo'] as String?) ?? '').trim();

    setState(() {
      _subjCtrl.text = assunto;
      _bodyCtrl.text = corpo;
    });
  }

  // Função para enviar e-mail dinamicamente
  Future<void> _enviarEmailDinamico() async {
    final to = _toCtrl.text.trim();
    final subject = _subjCtrl.text.trim();
    final rawBody = _bodyCtrl.text.trim(); // pode ser HTML ou texto simples

    if (to.isEmpty || subject.isEmpty || rawBody.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos.')),
      );
      return;
    }

    // Detecta se é HTML (igual ao registrar ocorrência)
    final bool isHtml = RegExp(
      r'</?(html|head|body|div|p|span|br|table|style|strong|em)\b',
      caseSensitive: false,
    ).hasMatch(rawBody);

    final String? htmlTemplate = isHtml ? rawBody : null;
    final String textTemplate = isHtml ? _stripHtml(rawBody) : rawBody;

    try {
      setState(() => _sending = true);

      final emailService = es.EmailBackendService();
      await emailService.enviarEmailViaBackend(
        to: to,
        subject: subject,
        body: textTemplate, // fallback texto
        htmlBody: htmlTemplate, // HTML dinâmico quando existir
        // Se quiser suportar tags aqui também, pode adicionar:
        // nomeGuardiao: ...,
        // textoSocorro: ...,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail enviado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  String _stripHtml(String html) {
    final noTags = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar E-mail')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Dropdown para selecionar o texto do e-mail
            DropdownButton<String>(
              value: _selectedMessage,
              hint: const Text('Selecione um texto de e-mail'),
              isExpanded: true,
              onChanged: (value) {
                setState(() {
                  _selectedMessage = value;
                });
                _onMessageSelected(value); // Preencher os campos
              },
              items: _textosEmails.map((String message) {
                return DropdownMenuItem<String>(
                  value: message,
                  child: Text(message),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Campo para o e-mail de destino
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(
                labelText: 'Para',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),

            // Campo para o assunto
            TextField(
              controller: _subjCtrl,
              decoration: const InputDecoration(
                labelText: 'Assunto',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Campo para o corpo da mensagem
            Expanded(
              child: TextField(
                controller: _bodyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Corpo da mensagem',
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                expands: true,
              ),
            ),
            const SizedBox(height: 16),

            // Botão para enviar e-mail dinamicamente
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _enviarEmailDinamico,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Enviar E-mail'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}