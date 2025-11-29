// lib/services/firestore.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Coleções principais
  final CollectionReference tipoOcorrencia =
      FirebaseFirestore.instance.collection('tipoOcorrencia');
  final CollectionReference usuario =
      FirebaseFirestore.instance.collection('usuario');
  final CollectionReference ocorrencias =
      FirebaseFirestore.instance.collection('ocorrencias');
  final CollectionReference guardioes =
      FirebaseFirestore.instance.collection('guardiões');
  final CollectionReference textosEmails =
      FirebaseFirestore.instance.collection('textosEmails');

  // ==============================================================
  // TIPOS DE OCORRÊNCIA
  // ==============================================================
  Stream<QuerySnapshot> getTipoOcorrenciaStream() {
    return _db
        .collection('tipoOcorrencia')
        .orderBy('tipoOcorrencia')
        .snapshots();
  }

  Future<void> addTipoOcorrencia(String tipoOcorrenciaText) async {
    final t = tipoOcorrenciaText.trim().toLowerCase();
    if (t.length < 3 || t.length > 100) {
      throw Exception("O tipo de ocorrência deve ter entre 3 e 100 caracteres.");
    }
    final dup =
        await tipoOcorrencia.where('tipoOcorrencia', isEqualTo: t).limit(1).get();
    if (dup.docs.isNotEmpty) {
      throw Exception("Este tipo de ocorrência já existe.");
    }
    await tipoOcorrencia.add({
      'tipoOcorrencia': t,
      'timestamp': FieldValue.serverTimestamp(),
      'inativar': false,
    });
  }

  Future<void> atualizarTipoOcorrencia(String docID, String novoTipo) async {
    final tipo = novoTipo.trim().toLowerCase();
    if (tipo.isEmpty || tipo.length < 3) {
      throw Exception("O tipo de ocorrência deve ter no mínimo 3 caracteres.");
    }
    await tipoOcorrencia.doc(docID).update({
      'tipoOcorrencia': tipo,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> inativarTipoOcorrencia(String docID) async {
    await tipoOcorrencia.doc(docID).update({
      'timestamp': FieldValue.serverTimestamp(),
      'inativar': true,
    });
  }

  // ==============================================================
  // CONSULTAS PARA GUARDIÃO
  // ==============================================================

  /// Ocorrências onde o usuário logado é guardião (id_guardiao é um array de UIDs)
  Stream<QuerySnapshot> getOcorrenciasDoGuardiaoStream(
    String guardiaoUid, {
    String? status,
  }) {
    Query q = ocorrencias.where('id_guardiao', arrayContains: guardiaoUid);

    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }

    return q.orderBy('criadoEm', descending: true).snapshots();
  }

  // ==============================================================
  // GUARDIÕES
  // ==============================================================

  // Função para convidar um guardião por e-mail
  Future<bool> convidarGuardiaoPorEmail(String email, String idUsuario) async {
    bool reativado = false;
    try {
      // 1) Buscar o usuário que será guardião pelo e-mail
      final QuerySnapshot userSnapshot =
          await usuario.where('email', isEqualTo: email).limit(1).get();

      if (userSnapshot.docs.isEmpty) {
        debugPrint(
          "Usuário não encontrado. Enviando convite para baixar o app."
        );
        // Aqui você pode disparar e-mail com link do app, se quiser
        return false;
      }

      final String idGuardiao = userSnapshot.docs.first.id;

      // 2) Verificar se já existe alguma relação usuário x guardião
      final QuerySnapshot relacaoSnapshot = await guardioes
          .where('id_usuario', isEqualTo: idUsuario)
          .where('id_guardiao', isEqualTo: idGuardiao)
          .limit(1) // em geral você só precisa de uma relação
          .get();

      if (relacaoSnapshot.docs.isNotEmpty) {
        final doc = relacaoSnapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final String status = (data['status'] ?? 'pendente') as String;

        if (status == 'inativo') {
          final DocumentSnapshot senderDoc = await usuario.doc(idUsuario).get();
          final String nomeUsuario = senderDoc.get('nome');

          await doc.reference.update({
            'nome_usuario': nomeUsuario,
            'invitado': true,
            'timestamp': Timestamp.now(),
            'status': 'pendente', // volta para pendente para reativar relacionamento
          });

          await usuario.doc(idUsuario).update({
            'guardioes_inativos': FieldValue.arrayRemove([idGuardiao]),
          });

          reativado = true;
          debugPrint(
            "Guardião estava inativo e foi reativado para novo convite.",
          );
          return reativado;
        }

        if (status == 'pendente') {
          // Já tem convite enviado e aguardando resposta
          throw Exception("Já existe um convite pendente para esse guardião.");
        }

        if (status == 'aceito' || status == 'ativo') {
          // Já é guardião, não faz sentido convidar de novo
          throw Exception("Esse usuário já é seu guardião.");
        }

        if (status == 'recusado') {
          // Convite foi recusado antes → reenvia usando o MESMO documento
          final DocumentSnapshot senderDoc = await usuario.doc(idUsuario).get();
          final String nomeUsuario = senderDoc.get('nome');

          await doc.reference.update({
            'nome_usuario': nomeUsuario,
            'invitado': true,
            'timestamp': Timestamp.now(),
            'status': 'pendente', // volta para pendente
          });

          debugPrint(
            "Convite reenviado para guardião que havia recusado anteriormente."
          );
          return reativado;
        }

        // Se aparecer algum outro status inesperado, você pode tratar aqui
      }

      // 3) Se não existe relação ainda, cria uma nova
      final DocumentSnapshot senderDoc = await usuario.doc(idUsuario).get();
      final String nomeUsuario = senderDoc.get('nome');

      await guardioes.add({
        'id_usuario': idUsuario,
        'nome_usuario': nomeUsuario,
        'id_guardiao': idGuardiao,
        'invitado': true,
        'timestamp': Timestamp.now(),
        'status': 'pendente',
      });
      return reativado;
    } catch (e) {
      debugPrint("Erro ao convidar guardião: $e");
      throw Exception("Erro ao convidar guardião: $e");
    }
  }

  // Função para aceitar o convite de guardião
  Future<void> aceitarConviteGuardiao(
      String conviteDocId, String idUsuario, String idGuardiao) async {
    await guardioes.doc(conviteDocId).update({
      'status': 'ativo',
      'timestamp': Timestamp.now(),
    });

    await usuario.doc(idUsuario).update({
      'guardioes': FieldValue.arrayUnion([idGuardiao]),
      'guardioes_inativos': FieldValue.arrayRemove([idGuardiao]),
    });

    await usuario.doc(idGuardiao).update({'guardiao': true});
  }

  // Função para recusar o convite de guardião
  Future<void> recusarConviteGuardiao(String conviteDocId) async {
    await guardioes.doc(conviteDocId).update({
      'status': 'recusado',
      'timestamp': Timestamp.now(),
    });
  }

  // Função para inativar o guardião
  Future<void> inativarGuardiao(String idUsuario, String idGuardiao) async {
    try {
      // Atualiza o status do guardião para 'inativo' na coleção 'guardiões'
      await guardioes
          .where('id_usuario', isEqualTo: idUsuario)
          .where('id_guardiao', isEqualTo: idGuardiao)
          .get()
          .then((querySnapshot) {
        for (final doc in querySnapshot.docs) {
          doc.reference.update({
            'status': 'inativo', // Marca o status como inativo
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      // Remove o guardião da lista de guardiões ativos
      await usuario.doc(idUsuario).update({
        'guardioes': FieldValue.arrayRemove([idGuardiao]),
      });

      // Adiciona o guardião à lista de guardiões inativos
      await usuario.doc(idUsuario).update({
        'guardioes_inativos': FieldValue.arrayUnion([idGuardiao]),
      });

      debugPrint("Guardião inativado com sucesso!");
    } catch (e) {
      debugPrint("Erro ao inativar guardião: $e");
      throw Exception("Erro ao inativar guardião: $e");
    }
  }

  // Função para reativar o guardião
  Future<void> reativarGuardiao(String idUsuario, String idGuardiao) async {
    try {
      // Atualiza o status do guardião para 'ativo' na coleção 'guardiões'
      await guardioes
          .where('id_usuario', isEqualTo: idUsuario)
          .where('id_guardiao', isEqualTo: idGuardiao)
          .get()
          .then((querySnapshot) {
        for (final doc in querySnapshot.docs) {
          doc.reference.update({
            'status': 'ativo', // Marca o status como ativo
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      // Adiciona o guardião de volta à lista de guardiões ativos
      await usuario.doc(idUsuario).update({
        'guardioes': FieldValue.arrayUnion([idGuardiao]),
      });

      // Remove o guardião da lista de guardiões inativos
      await usuario.doc(idUsuario).update({
        'guardioes_inativos': FieldValue.arrayRemove([idGuardiao]),
      });

      debugPrint("Guardião reativado com sucesso!");
    } catch (e) {
      debugPrint("Erro ao reativar guardião: $e");
      throw Exception("Erro ao reativar guardião: $e");
    }
  }

  // Função para pegar os convites pendentes de um guardião
  Stream<QuerySnapshot> getConvitesRecebidosGuardiao(String idGuardiao) {
    return guardioes
        .where('id_guardiao', isEqualTo: idGuardiao)
        .where('status', isEqualTo: 'pendente')
        .snapshots();
  }

  // ==============================================================
  // USUÁRIO
  // ==============================================================
  Future<void> addUsuario(String uid, Map<String, dynamic> dadosUsuario) async {
    await usuario.doc(uid).set({
      'nome': dadosUsuario['nome'],
      'email': dadosUsuario['email'],
      'cpf': dadosUsuario['cpf'],
      'numerotelefone': dadosUsuario['numerotelefone'],
      'dataNasc': dadosUsuario['dataNasc'],
      'sexo': dadosUsuario['sexo'],
      'inativar': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getUsuarioStream() {
    return usuario
        .where('inativar', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> atualizarUsuario(
      String uid, Map<String, dynamic> dadosUsuario) async {
    await usuario.doc(uid).update({
      ...dadosUsuario,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> inativarUsuario(String uid) async {
    await usuario.doc(uid).update({
      'timestamp': FieldValue.serverTimestamp(),
      'inativar': true,
    });
  }

  // ==============================================================
  // UPLOAD HELPERS (Storage)
  // ==============================================================
  String _guessContentType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.m4v':
        return 'video/x-m4v';
      case '.avi':
        return 'video/x-msvideo';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.m4a':
        return 'audio/mp4';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> _uploadArquivoParaStorage({
    required String pathLocal,
    required String uid,
    required String ocId,
  }) async {
    final file = File(pathLocal);
    if (!await file.exists()) {
      throw Exception('Arquivo local não encontrado para upload: $pathLocal');
    }
    final fileName = p.basename(pathLocal);
    final ref =
        FirebaseStorage.instance.ref().child('ocorrencias/$uid/$ocId/$fileName');

    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: _guessContentType(fileName)),
    );
    return await task.ref.getDownloadURL();
  }

  /// Salva referência de mídia (foto/áudio) dentro da ocorrência.
  Future<void> registrarMidiaSos({
    required String ocorrenciaId,
    required String type, // 'photo' | 'audio' | 'video'
    required String url,
  }) async {
    await ocorrencias.doc(ocorrenciaId).collection('midias').add({
      'type': type,
      'url': url,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // NOVO: cria uma ocorrência SOS vinculando TODOS os guardiões aceitos/ativos da vítima.
  Future<String> abrirSosComGuardioes({
    required String ownerUid,
    required String textoSocorro,
    double? latitude,
    double? longitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    // Busca guardiões com status aceito ou ativo
    final aceitosSnap = await guardioes
        .where('id_usuario', isEqualTo: ownerUid)
        .where('status', whereIn: ['aceito', 'ativo'])
        .get();

    final idsSet = <String>{};

    for (final doc in aceitosSnap.docs) {
      final idG = (doc['id_guardiao'] as String?) ?? '';
      if (idG.isNotEmpty) idsSet.add(idG);
    }

    final listaGuardioes = idsSet.toList();

    // Cria ocorrência SOS SEM mídia (anexos vazios)
    final ocId = await addOcorrencia(
      'SOS',
      'Gravíssima',
      'SOS acionado pelo usuário',
      textoSocorro,
      true,
      anexosLocais: const [],
      latitude: latitude,
      longitude: longitude,
      idGuardiao: listaGuardioes,
      ownerUid: ownerUid,
      isSos: true, // deixa explícito que é SOS
      dataHoraAbertura: DateTime.now(),
    );

    return ocId;
  }

  // ==============================================================
  // OCORRÊNCIAS (LOCAL + NUVEM)
  // ==============================================================

  /// Cria uma ocorrência (normal ou SOS).
  Future<String> addOcorrencia(
    String tipo,
    String gravidade,
    String relato,
    String textoSocorro,
    bool enviarParaGuardiao, {
    List<String>? anexosLocais,
    double? latitude,          // ainda usado pelo fluxo SOS
    double? longitude,
    List<String>? idGuardiao,  // Lista de IDs de guardiões
    required String ownerUid,  // ID do usuário criador da ocorrência

    // novos parâmetros para compatibilizar com tela_registrar_ocorrencia.dart
    bool? isSos,
    double? latitudeInicial,
    double? longitudeInicial,
    DateTime? dataHoraAbertura,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final midiasLocais = List<String>.from(anexosLocais ?? const []);
    final bool sosFlag = isSos ?? (tipo.toUpperCase() == 'SOS');

    // Se latitude/longitude "diretas" não vierem, usa as iniciais
    final double? latEfetiva = latitude ?? latitudeInicial;
    final double? lonEfetiva = longitude ?? longitudeInicial;
    final DateTime agora = dataHoraAbertura ?? DateTime.now();
    final List<String> guardioes = List<String>.from(idGuardiao ?? const []);

    final Map<String, dynamic> baseData = {
    'ownerUid': ownerUid,
    'id_guardiao': guardioes,
    'status': 'aberto',
    'gravidade': gravidade,
    'relato': relato,
    'textoSocorro': textoSocorro,
    'tipoOcorrencia': tipo,
    'criadoEm': FieldValue.serverTimestamp(),
    'anexosLocais': midiasLocais,
    'anexos': [],
    'isSos': sosFlag,
};


    if (latEfetiva != null) baseData['latitude'] = latEfetiva;
    if (lonEfetiva != null) baseData['longitude'] = lonEfetiva;

    // Criação do documento de ocorrência
    final ocRef = await ocorrencias.add(baseData);

    final ocId = ocRef.id;

    // Upload dos anexos locais, se houver
    if (midiasLocais.isNotEmpty) {
      final uploadFutures = midiasLocais.map((localPath) async {
        try {
          return await _uploadArquivoParaStorage(
            pathLocal: localPath,
            uid: user.uid,
            ocId: ocId,
          );
        } catch (e) {
          debugPrint('Falha ao enviar $localPath: $e');
          return null;
        }
      }).toList();

      final urlsCloud =
          (await Future.wait(uploadFutures)).whereType<String>().toList();

      if (urlsCloud.isNotEmpty) {
        await ocRef.update({'anexos': urlsCloud});
      }

      // Histórico inicial, se não for SOS
      if (!sosFlag) {
        await ocRef.collection('historico').add({
          'acao': 'criado',
          'autorUid': user.uid,
          'tipoOcorrencia': tipo,
          'gravidade': gravidade,
          'relato': relato,
          'textoSocorro': textoSocorro,
          'latitude': latEfetiva,
          'longitude': lonEfetiva,
          'criadoEm': FieldValue.serverTimestamp(),
          'midiasLocais': midiasLocais,
          'midiasCloud': urlsCloud,
        });
      }
    } else {
      // Sem anexos locais
      if (!sosFlag) {
        await ocRef.collection('historico').add({
          'acao': 'criado',
          'autorUid': user.uid,
          'tipoOcorrencia': tipo,
          'gravidade': gravidade,
          'relato': relato,
          'textoSocorro': textoSocorro,
          'latitude': latEfetiva,
          'longitude': lonEfetiva,
          'criadoEm': FieldValue.serverTimestamp(),
          'midiasLocais': const <String>[],
          'midiasCloud': const <String>[],
        });
      }
    }

    return ocId;
  }

  /// Atualiza relato e acrescenta/remover anexos **locais**.
  Future<void> editarOcorrenciaLocal(
    String ocorrenciaId, {
    String? novoRelato,
    List<String>? caminhosNovos,
    List<String>? caminhosParaRemover,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final ref = ocorrencias.doc(ocorrenciaId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ocorrência não encontrada');

    final data = snap.data() as Map<String, dynamic>;
    final isSOS =
        ((data['tipoOcorrencia'] as String?) ?? '').toUpperCase() == 'SOS';

    final relatoAntigo = (data['relato'] as String?) ?? '';
    final existentes =
        (data['anexosLocais'] as List?)?.cast<String>() ?? <String>[];

    final addLocais = List<String>.from(caminhosNovos ?? const []);
    final rmLocais = List<String>.from(caminhosParaRemover ?? const []);

    final atualizados = <String>[
      for (final p in existentes)
        if (!rmLocais.contains(p)) p,
      ...addLocais,
    ];

    final relatoFinal = (novoRelato ?? relatoAntigo).trim();

    await ref.update({
      'relato': relatoFinal,
      'anexosLocais': atualizados,
      'ultimaAtualizacao': FieldValue.serverTimestamp(),
    });

    // histórico somente se NÃO for SOS
    if (!isSOS) {
      await ref.collection('historico').add({
        'acao': 'edicao',
        'autorUid': user.uid,
        'criadoEm': FieldValue.serverTimestamp(),
        'relatoAnterior': relatoAntigo,
        'novoRelato': relatoFinal,
        'adicionadosLocais': addLocais,
        'removidosLocais': rmLocais,
      });
    }
  }

  /// Atualiza relato + acrescenta anexos locais e **URLs de nuvem** (Storage).
  Future<void> editarOcorrenciaHibrido(
    String ocorrenciaId, {
    required String novoRelato,
    required List<String> caminhosNovosLocais,
    required List<String> urlsNovasCloud,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final ref = ocorrencias.doc(ocorrenciaId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('Ocorrência não encontrada');
      }
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final isSOS =
          ((data['tipoOcorrencia'] as String?) ?? '').toUpperCase() == 'SOS';

      final relatoAntigo = (data['relato'] as String?) ?? '';

      final anexosLocaisAtuais =
          (data['anexosLocais'] as List?)?.cast<String>() ?? <String>[];
      final anexosCloudAtuais =
          (data['anexos'] as List?)?.cast<String>() ?? <String>[];

      final novosLocais = <String>[
        ...anexosLocaisAtuais,
        ...caminhosNovosLocais,
      ];
      final novosCloud = <String>[
        ...anexosCloudAtuais,
        ...urlsNovasCloud,
      ];

      tx.update(ref, {
        'relato': novoRelato.trim(),
        'anexosLocais': novosLocais,
        'anexos': novosCloud,
        'ultimaAtualizacao': FieldValue.serverTimestamp(),
      });

      // histórico somente se NÃO for SOS
      if (!isSOS) {
        final histRef = ref.collection('historico').doc();
        tx.set(histRef, {
          'acao': 'editado',
          'autorUid': user.uid,
          'criadoEm': FieldValue.serverTimestamp(),
          'relatoAnterior': relatoAntigo,
          'novoRelato': novoRelato.trim(),
          'adicionadosLocais': caminhosNovosLocais,
          'adicionadosCloud': urlsNovasCloud,
          'removidosLocais': <String>[],
        });
      }
    });
  }

  /// Remove 1 arquivo local do documento e cria item de histórico próprio.
  Future<void> removerAnexoLocal(String ocorrenciaId, String caminhoLocal) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final ref = ocorrencias.doc(ocorrenciaId);

    // ler doc para saber se é SOS
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final isSOS =
        ((data['tipoOcorrencia'] as String?) ?? '').toUpperCase() == 'SOS';

    await ref.update({
      'anexosLocais': FieldValue.arrayRemove([caminhoLocal]),
      'ultimaAtualizacao': FieldValue.serverTimestamp(),
    });

    // histórico somente se NÃO for SOS
    if (!isSOS) {
      await ref.collection('historico').add({
        'acao': 'remocao_local',
        'autorUid': user.uid,
        'criadoEm': FieldValue.serverTimestamp(),
        'adicionadosLocais': const <String>[],
        'adicionadosCloud': const <String>[],
        'removidosLocais': [caminhoLocal],
      });
    }
  }

  // ==============================================================
  // CONSULTAS / STATUS
  // ==============================================================
  Stream<QuerySnapshot> getOcorrenciasDoUsuarioStream(
    String uid, {
    String? status,
  }) {
    Query q = ocorrencias.where('ownerUid', isEqualTo: uid);
    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }
    return q.orderBy('criadoEm', descending: true).snapshots();
  }

  /// Agora filtra apenas o SOS aberto (`isSos == true`),
  /// para o tracker não pegar ocorrência normal.
  Future<String?> _getSosAbertoDocIdAtual() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final snap = await ocorrencias
        .where('ownerUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'aberto')
        .where('isSos', isEqualTo: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> updateLocalizacaoSosAberto({
    required double latitude,
    required double longitude,
  }) async {
    final docId = await _getSosAbertoDocIdAtual();
    if (docId == null) return;

    await ocorrencias.doc(docId).update({
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Encerra o SOS aberto do usuário atual e retorna o `docId` finalizado (ou null).
  Future<String?> encerrarSosAberto() async {
    final docId = await _getSosAbertoDocIdAtual();
    if (docId == null) return null;

    await ocorrencias.doc(docId).update({
      'status': 'finalizado',
      'finalizadoEm': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    return docId;
  }

  Future<void> finalizarOcorrencia(String ocorrenciaId) async {
    await ocorrencias.doc(ocorrenciaId).update({
      'status': 'finalizado',
      'finalizadoEm': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ==============================================================
  // TEXTOS DE E-MAIL
  // ==============================================================
  Future<void> cadastrarTextoEmail(
      String nome, String textoEmail, bool inativar) async {
    await textosEmails.add({
      'nome': nome.trim(),
      'textoEmail': textoEmail.trim(),
      'inativar': inativar,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> alterarTextoEmail(
      String id, String nome, String textoEmail, bool inativar) async {
    await textosEmails.doc(id).update({
      'nome': nome.trim(),
      'textoEmail': textoEmail.trim(),
      'inativar': inativar,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> excluirTextosEmails(String docId) async {
    await textosEmails.doc(docId).delete();
  }

  Stream<QuerySnapshot> listarTextoEmailAtivo() {
    return textosEmails.where('inativar', isEqualTo: false).snapshots();
  }

  Future<String?> buscarTextoEmailPorNome(String nomeEmail) async {
    try {
      final snapshot = await textosEmails
          .where('nome', isEqualTo: nomeEmail)
          .where('inativar', isEqualTo: false)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first['textoEmail']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint("Erro ao buscar texto de e-mail: $e");
      return null;
    }
  }

  Future<QueryDocumentSnapshot<Object?>?> buscarTextoEmail(String nome) async {
    try {
      final qs =
          await textosEmails.where('nome', isEqualTo: nome).limit(1).get();
      if (qs.docs.isNotEmpty) return qs.docs.first;
      return null;
    } catch (e) {
      debugPrint("Erro ao buscar o texto de e-mail: $e");
      return null;
    }
  }

  Stream<QuerySnapshot> listarTodosTextosEmail() {
    return textosEmails.orderBy('timestamp', descending: true).snapshots();
  }

  Future<List<String>> listarNomesTextosEmails() async {
    final query = await textosEmails.where('inativar', isEqualTo: false).get();
    return query.docs
        .map((doc) => (doc['nome'] ?? '').toString())
        .where((nome) => nome.isNotEmpty)
        .toList();
  }

  // ==============================================================
  // CONFIGS GENÉRICAS
  // ==============================================================
  Future<void> cadastrarConfig(String campo, String valor, bool ativo) async {
    await FirebaseFirestore.instance.collection('config').add({
      'campo': campo.trim(),
      'valor': valor.trim(),
      'ativo': ativo,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot?> buscarConfigPorCampo(String campo) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('config')
        .where('campo', isEqualTo: campo)
        .where('ativo', isEqualTo: true)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) return snapshot.docs.first;
    return null;
  }

  Future<void> alterarConfig(String docId, String novoValor, bool ativo) async {
    await FirebaseFirestore.instance.collection('config').doc(docId).update({
      'valor': novoValor.trim(),
      'ativo': ativo,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> listarConfigsAtivas() {
    return FirebaseFirestore.instance
        .collection('config')
        .where('ativo', isEqualTo: true)
        .snapshots();
  }

  Future<void> excluirConfig(String docId) async {
    await FirebaseFirestore.instance.collection('config').doc(docId).delete();
  }

  Future<void> toggleAtivoGenerico(
      String collection, String docId, bool inativar) async {
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .update({
        'inativar': inativar,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Erro ao alternar status: $e');
    }
  }
}