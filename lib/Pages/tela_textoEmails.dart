import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crud/services/firestore.dart' as fsFirestore;
import 'package:crud/services/enviar_email.dart' as es;
import 'package:crud/theme/app_colors.dart';

class TelaTextoEmails extends StatefulWidget {
  const TelaTextoEmails({Key? key}) : super(key: key);

  @override
  State<TelaTextoEmails> createState() => _TelaTextoEmailsState();
}

class _TelaTextoEmailsState extends State<TelaTextoEmails> {
  final fsFirestore.FirestoreService firestoreService =
      fsFirestore.FirestoreService();
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _textoController = TextEditingController();

  // Documento selecionado para edição
  QueryDocumentSnapshot<Map<String, dynamic>>? _selectedDoc;

  // Tags suportadas pelo backend de e-mail
  String? _selectedTag;
  final List<String> _tags = es.EmailBackendService.supportedTags;

  // Estado de ativo/inativo
  bool _ativo = true;

  // Controle se está em modo edição
  bool isEditing = false;

  // ==========================
  // Buscar texto pelo nome (opcional)
  // ==========================
  Future<void> _buscarTextoEmail(String nome) async {
    if (nome.isEmpty) return;

    final docSnapshot = await firestoreService.buscarTextoEmail(nome);
    if (docSnapshot != null) {
      setState(() {
        _selectedDoc = docSnapshot;
        _nomeController.text = docSnapshot['nome'] ?? '';
        _textoController.text =
            docSnapshot['textoEmail'] ?? docSnapshot['corpo'] ?? '';
        _ativo = !(docSnapshot['inativar'] ?? false);
        isEditing = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo não encontrado ou inativo.')),
      );
    }
  }

  // ==========================
  // Salvar/atualizar texto de e-mail
  // ==========================
  Future<void> _salvarTextoEmail() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios!')),
      );
      return;
    }

    try {
      if (_selectedDoc != null) {
        await firestoreService.alterarTextoEmail(
          _selectedDoc!.id,
          _nomeController.text.trim(),
          _textoController.text.trim(),
          !_ativo, // inativar = !ativo
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Texto de e-mail atualizado com sucesso!')),
        );

        setState(() {
          _selectedDoc = null;
          isEditing = false;
          _nomeController.clear();
          _textoController.clear();
          _ativo = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // ==========================
  // Inserir TAG no texto
  // ==========================
  void _insertTagInFocusedField() {
    final tag = _selectedTag;
    if (tag == null) return;

    final targetCtrl = _textoController;
    final textoAtual = targetCtrl.text;
    targetCtrl.text = '$textoAtual $tag';
    targetCtrl.selection =
        TextSelection.fromPosition(TextPosition(offset: targetCtrl.text.length));
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _textoController.dispose();
    super.dispose();
  }

  // ==========================
  // Build
  // ==========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Texto de E-mail'),
        backgroundColor: AppColors.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ==========================
            // Área de edição (só aparece se tiver algo selecionado)
            // ==========================
            if (isEditing)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Nome do texto
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Texto de E-mail',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Campo obrigatório'
                              : null,
                    ),
                    const SizedBox(height: 12),

                    // Corpo do e-mail
                    TextFormField(
                      controller: _textoController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Texto do E-mail',
                        border: OutlineInputBorder(),
                        hintText: 'Conteúdo do e-mail enviado ao guardião/usuário',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Campo obrigatório'
                              : null,
                    ),
                    const SizedBox(height: 12),

                    // Ativo / Inativo
                    Row(
                      children: [
                        Checkbox(
                          value: _ativo,
                          onChanged: (v) {
                            setState(() => _ativo = v ?? true);
                          },
                        ),
                        const Text('Ativo'),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tags
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedTag,
                            hint: const Text('Tags disponíveis'),
                            isExpanded: true,
                            onChanged: (v) => setState(() => _selectedTag = v),
                            items: _tags
                                .map(
                                  (t) => DropdownMenuItem<String>(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _insertTagInFocusedField,
                          icon: const Icon(Icons.input),
                          label: const Text('Inserir'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Botão salvar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _salvarTextoEmail,
                        child: const Text('Atualizar'),
                      ),
                    ),
                    const Divider(height: 24),
                  ],
                ),
              ),

            // ==========================
            // Lista de modelos de e-mail
            // ==========================
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firestoreService.listarTodosTextosEmail(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('Nenhum texto de e-mail cadastrado.'),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final nome = doc['nome'] ?? '';
                      final inativar = doc['inativar'] ?? false;

                      return Card(
                        child: ListTile(
                          title: Text(nome),
                          subtitle: Text(
                            inativar ? 'Inativo' : 'Ativo',
                            style: TextStyle(
                              color: inativar ? Colors.red : Colors.green,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isEditing && _selectedDoc?.id == doc.id
                                  ? Icons.edit
                                  : Icons.edit_outlined,
                              color: isEditing && _selectedDoc?.id == doc.id
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            onPressed: () {
                              setState(() {
                                if (_selectedDoc?.id == doc.id && isEditing) {
                                  // Se clicar de novo no mesmo: cancela edição
                                  _selectedDoc = null;
                                  isEditing = false;
                                  _nomeController.clear();
                                  _textoController.clear();
                                  _ativo = true;
                                } else {
                                  // Entrar em modo edição
                                  _selectedDoc = doc;
                                  _nomeController.text = nome;
                                  _textoController.text =
                                      doc['textoEmail'] ?? doc['corpo'] ?? '';
                                  _ativo = !(doc['inativar'] ?? false);
                                  isEditing = true;
                                }
                              });
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
