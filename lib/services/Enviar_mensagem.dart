import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Função para buscar a mensagem no Firestore
Future<String?> buscarMensagemPorCampo(String nome) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('textoEmails')
      .where('nome', isEqualTo: nome)
      .where('inativar', isEqualTo: false)
      .limit(1)
      .get();

  if (snapshot.docs.isNotEmpty) {
    return snapshot.docs.first.get('textoEmail') as String;
  }
  return null;
}

// Função para substituir as variáveis no corpo da mensagem
Future<String> preencherVariaveisMensagem(String template) async {
  Map<String, String> variaveis = {};

  // Obter dados do usuário logado
  User? usuario = FirebaseAuth.instance.currentUser;
  if (usuario != null) {
    // Nome do usuário logado
    String nomeUsuario = usuario.displayName ?? 'Usuário sem nome';
    variaveis['nome'] = nomeUsuario;

    // E-mail do usuário logado
    String emailUsuario = usuario.email ?? 'E-mail não encontrado';
    variaveis['email'] = emailUsuario;

    // Hora atual
    String horaAtual = DateTime.now().toString();
    variaveis['hora'] = horaAtual;

    // Obter pessoas às quais o usuário é guardião
    List<String> guardioes = await obterGuardioes(usuario.uid);
    variaveis['guardioes'] = guardioes.join(', '); // Lista de guardiões separada por vírgula
  }

  // Substituir as variáveis no template
  return preencherVariaveis(template, variaveis);
}

// Função para preencher as variáveis no template
String preencherVariaveis(String template, Map<String, String> variaveis) {
  String mensagem = template;
  variaveis.forEach((key, value) {
    mensagem = mensagem.replaceAll('{$key}', value);
  });
  return mensagem;
}

// Função para obter as pessoas às quais o usuário é guardião
Future<List<String>> obterGuardioes(String idUsuario) async {
  List<String> guardioes = [];
  QuerySnapshot snapshot = await FirebaseFirestore.instance
      .collection('guardiões')
      .where('id_usuario', isEqualTo: idUsuario)
      .get();

  for (var doc in snapshot.docs) {
    guardioes.add(doc['nome_guardiao']); // Nome do guardião
  }

  return guardioes;
}
void enviarMensagem() async {
  // Buscar a mensagem do template
  String? template = await buscarMensagemPorCampo('mensagemDeBoasVindas');

  if (template != null) {
    // Preencher as variáveis da mensagem
    String mensagemFinal = await preencherVariaveisMensagem(template);

    // Enviar a mensagem final com as variáveis substituídas
    print(mensagemFinal);
  } else {
    print('Mensagem não encontrada.');
  }
}