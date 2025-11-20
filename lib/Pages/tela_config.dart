import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({Key? key}) : super(key: key);

  @override
  _ConfigScreenState createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final CollectionReference configs =
      FirebaseFirestore.instance.collection('configs');

  final _formKey = GlobalKey<FormState>();
  final TextEditingController campoController = TextEditingController();
  final TextEditingController valorController = TextEditingController();
  bool ativo = true;

  String? editingDocId;

  void clearForm() {
    campoController.clear();
    valorController.clear();
    ativo = true;
    editingDocId = null;
  }

  Future<void> salvarConfig() async {
    if (_formKey.currentState!.validate()) {
      if (editingDocId == null) {
        // Cadastrar novo
        await configs.add({
          'campo': campoController.text.trim(),
          'valor': valorController.text.trim(),
          'ativo': ativo,
          'timestamp': Timestamp.now(),
        });
      } else {
        // Atualizar existente
        await configs.doc(editingDocId).update({
          'campo': campoController.text.trim(),
          'valor': valorController.text.trim(),
          'ativo': ativo,
          'timestamp': Timestamp.now(),
        });
      }
      clearForm();
    }
  }

  void carregarParaEdicao(DocumentSnapshot doc) {
    setState(() {
      editingDocId = doc.id;
      campoController.text = doc['campo'];
      valorController.text = doc['valor'];
      ativo = doc['ativo'];
    });
  }

  Future<void> excluirConfig(String docId) async {
    await configs.doc(docId).delete();
    if (editingDocId == docId) {
      clearForm();
    }
  }

  @override
  void dispose() {
    campoController.dispose();
    valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurações'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: campoController,
                    decoration: InputDecoration(labelText: 'Campo'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o nome do campo';
                      }
                      return null;
                    },
                    enabled: editingDocId == null, // Não pode alterar o campo no editar
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: valorController,
                    decoration: InputDecoration(labelText: 'Valor'),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o valor';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 8),
                  SwitchListTile(
                    title: Text('Ativo'),
                    value: ativo,
                    onChanged: (val) {
                      setState(() {
                        ativo = val;
                      });
                    },
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await salvarConfig();
                      setState(() {}); // Atualiza lista
                    },
                    child: Text(editingDocId == null ? 'Cadastrar' : 'Atualizar'),
                  ),
                  if (editingDocId != null)
                    TextButton(
                      onPressed: () {
                        clearForm();
                        setState(() {});
                      },
                      child: Text('Cancelar edição'),
                    ),
                ],
              ),
            ),
            Divider(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: configs.orderBy('timestamp', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Erro: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(child: Text('Nenhuma configuração encontrada.'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var doc = docs[index];
                      return ListTile(
                        title: Text(doc['campo']),
                        subtitle: Text(doc['valor']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              doc['ativo'] ? Icons.check_circle : Icons.cancel,
                              color: doc['ativo'] ? Colors.green : Colors.red,
                            ),
                            IconButton(
                              icon: Icon(Icons.edit),
                              onPressed: () => carregarParaEdicao(doc),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Text('Confirmar exclusão'),
                                  content: Text(
                                      'Deseja realmente excluir a configuração "${doc['campo']}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        excluirConfig(doc.id);
                                        Navigator.pop(context);
                                      },
                                      child: Text('Excluir'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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