import 'package:crud/services/firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TipoOcorrencia extends StatefulWidget {
  const TipoOcorrencia({super.key});

  @override
  State<TipoOcorrencia> createState() => _TipoOcorrenciaState();
}

class _TipoOcorrenciaState extends State<TipoOcorrencia> {
  final FirestoreService firestoreService = FirestoreService();
  final TextEditingController textController = TextEditingController();

  // Método para abrir o diálogo e adicionar tipo ocorrência
  void openAdicionarTipoOcorrenciaBox() {
    textController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Adicionar Tipo de Ocorrência"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: "Digite o tipo de ocorrência",
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              try {
                await firestoreService.addTipoOcorrencia(textController.text);
                textController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Tipo de ocorrência adicionado.")),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
            child: const Text("Adicionar"),
          ),
        ],
      ),
    );
  }

  // Método para abrir o diálogo e atualizar o tipo ocorrência
  void openAtualizarTipoOcorrenciaBox(String docID, String tipoAtual) {
    textController.text = tipoAtual;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Atualizar Tipo de Ocorrência"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: "Atualize o tipo de ocorrência",
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              try {
                await firestoreService.atualizarTipoOcorrencia(docID, textController.text);
                textController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Tipo de ocorrência atualizado.")),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
            child: const Text("Atualizar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tipo de Ocorrência")),
      floatingActionButton: FloatingActionButton(
        onPressed: openAdicionarTipoOcorrenciaBox,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getTipoOcorrenciaStream(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            List tipoOcorrenciaList = snapshot.data!.docs;
            return ListView.builder(
              itemCount: tipoOcorrenciaList.length,
              itemBuilder: (context, index) {
                DocumentSnapshot document = tipoOcorrenciaList[index];
                String docID = document.id;

                Map<String, dynamic> data = document.data() as Map<String, dynamic>;
                String tipoOcorrenciaText = data['tipoOcorrencia'];

                return ListTile(
                  title: Text(tipoOcorrenciaText),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Atualizar (Editar)
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => openAtualizarTipoOcorrenciaBox(docID, tipoOcorrenciaText),
                      ),

                      // Inativar (Excluir)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          firestoreService.inativarTipoOcorrencia(docID);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Tipo de ocorrência inativado.")),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          } else {
            return const Center(child: Text("Não tem tipo de ocorrência"));
          }
        },
      ),
    );
  }
}