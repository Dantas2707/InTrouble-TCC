import 'dart:io';
import 'package:crud/services/firestore.dart';
import 'package:crud/services/local_media.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:crud/services/sms_service.dart';
import 'package:crud/theme/app_colors.dart';

class OcorrenciasPage extends StatefulWidget {
  const OcorrenciasPage({super.key});

  @override
  State<OcorrenciasPage> createState() => _OcorrenciasPageState();
}

class _OcorrenciasPageState extends State<OcorrenciasPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FirestoreService _service = FirestoreService();
  late final String _uid;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }
    _uid = user.uid;
    _tabController = TabController(length: 2, vsync: this); // Abertas | Finalizadas
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Stream ordenada no servidor
  Stream<QuerySnapshot> _streamOcorrenciasDoUsuario() {
    return FirebaseFirestore.instance
        .collection('ocorrencias')
        .where('ownerUid', isEqualTo: _uid)
        .orderBy('criadoEm', descending: true)
        .snapshots();
  }

  // ====== Helpers de upload (para edição) ======
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
  // ============================================

  // ========= Helpers para URLs (SOS) =========
  List<String> _coletarUrlsDeMidia(Map<String, dynamic> data) {
    final urls = <String>[];

    void addIfUrl(dynamic v) {
      if (v is String) {
        final s = v.trim();
        if (s.startsWith('http://') || s.startsWith('https://')) {
          urls.add(s);
        }
      } else if (v is List) {
        for (final item in v) addIfUrl(item);
      } else if (v is Map) {
        for (final item in v.values) addIfUrl(item);
      }
    }

    const possiveisChaves = <String>[
      'anexos',
      'anexosUrls',
      'anexosCloud',
      'midias',
      'media',
      'mediaUrls',
      'capturas',
      'capturasUrls',
      'urls',
    ];

    for (final k in possiveisChaves) {
      addIfUrl(data[k]);
    }

    // fallback: varredura superficial
    if (urls.isEmpty) {
      for (final v in data.values) {
        addIfUrl(v);
      }
    }

    return urls.toSet().toList(); // sem duplicadas
  }

  bool _isImagemUrl(String u) {
    final l = u.toLowerCase();
    return l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.gif') ||
        l.endsWith('.webp') ||
        l.endsWith('.heic');
  }

  IconData _iconeParaUrl(String u) {
    final l = u.toLowerCase();
    if (l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.m4v') || l.endsWith('.avi')) {
      return Icons.play_circle_fill;
    }
    if (l.endsWith('.mp3') || l.endsWith('.wav') || l.endsWith('.aac')) {
      return Icons.audiotrack;
    }
    if (l.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    }
    return Icons.link;
  }

  Future<void> _abrirUrlNoNavegador(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      final fallback = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!fallback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link:\n$url')),
        );
      }
    }
  }

  // =========================================================
  //              HELPERS DE SMS (EDIÇÃO / FINALIZAÇÃO)
  // =========================================================

  /// Busca o nome do usuário dono das ocorrências (vítima).
  Future<String> _obterNomeUsuario() async {
    String nome = 'Usuário';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(_uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        nome = (data['nome'] ?? nome).toString();
      }
    } catch (e) {
      debugPrint('Erro ao obter nome do usuário: $e');
    }
    return nome;
  }

  /// Busca os telefones dos guardiões a partir da lista de IDs
  Future<List<String>> _obterTelefonesGuardioes(
      List<dynamic> idsGuardioes) async {
    final List<String> telefones = [];

    for (final gId in idsGuardioes) {
      if (gId == null) continue;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuario')
            .doc(gId.toString())
            .get();

        if (!doc.exists || doc.data() == null) continue;

        final data = doc.data() as Map<String, dynamic>;
        final phone = (data['numerotelefone'] ?? '').toString().trim();

        if (phone.isEmpty) {
          debugPrint('Guardião $gId sem número de telefone cadastrado.');
          continue;
        }

        telefones.add(phone);
      } catch (e) {
        debugPrint('Erro ao processar guardião $gId: $e');
      }
    }

    return telefones;
  }

  /// Notifica guardiões que a ocorrência foi ATUALIZADA (edição)
  Future<void> _enviarSmsAtualizacaoOcorrencia({
    required List<dynamic> idsGuardioes,
    required String nomeUsuario,
    required String tipo,
    required String gravidade,
  }) async {
    if (idsGuardioes.isEmpty) {
      debugPrint('Ocorrência sem guardiões vinculados (edição), não enviando SMS.');
      return;
    }

    final telefones = await _obterTelefonesGuardioes(idsGuardioes);
    if (telefones.isEmpty) {
      debugPrint('Nenhum telefone de guardião encontrado para edição.');
      return;
    }

    final tipoComGravidade =
        gravidade.isNotEmpty ? '$tipo (Gravidade: $gravidade)' : tipo;

    await SmsService.instance.smsOcorrenciaEditada(
      telefonesGuardioes: telefones,
      nomeVitima: nomeUsuario,
      tipoOcorrencia: tipoComGravidade,
    );
  }

  /// Notifica guardiões que a ocorrência foi FINALIZADA
  Future<void> _enviarSmsFinalizacaoOcorrencia({
    required List<dynamic> idsGuardioes,
    required String nomeUsuario,
    required String tipo,
    required String gravidade,
  }) async {
    if (idsGuardioes.isEmpty) {
      debugPrint('Ocorrência sem guardiões vinculados (finalização), não enviando SMS.');
      return;
    }

    final telefones = await _obterTelefonesGuardioes(idsGuardioes);
    if (telefones.isEmpty) {
      debugPrint('Nenhum telefone de guardião encontrado para finalização.');
      return;
    }

    final tipoComGravidade =
        gravidade.isNotEmpty ? '$tipo (Gravidade: $gravidade)' : tipo;

    await SmsService.instance.smsOcorrenciaFinalizada(
      telefonesGuardioes: telefones,
      nomeVitima: nomeUsuario,
      tipoOcorrencia: tipoComGravidade,
    );
  }

  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        title: const Text(
          'Minhas ocorrências',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Abertas'),
            Tab(text: 'Finalizadas'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
        ),
      ),
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acompanhe suas ocorrências',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Veja o histórico dos registros, acompanhe anexos e finalize casos já resolvidos.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _streamOcorrenciasDoUsuario(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar ocorrências:\n${snap.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final todos = snap.data?.docs ?? [];

                // Comparação segura: usa maps (nada de doc['campo'])
                int compareDesc(
                    QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
                  final ma = (a.data() as Map<String, dynamic>? ?? const {});
                  final mb = (b.data() as Map<String, dynamic>? ?? const {});
                  final ta = (ma['criadoEm'] as Timestamp?);
                  final tb = (mb['criadoEm'] as Timestamp?);
                  final da = (ta?.toDate()) ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final db = (tb?.toDate()) ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                }

                final abertas = [...todos]
                  ..retainWhere((d) {
                    final m = (d.data() as Map<String, dynamic>? ?? const {});
                    return (m['status'] ?? '') == 'aberto';
                  })
                  ..sort(compareDesc);

                final finalizadas = [...todos]
                  ..retainWhere((d) {
                    final m = (d.data() as Map<String, dynamic>? ?? const {});
                    return (m['status'] ?? '') == 'finalizado';
                  })
                  ..sort(compareDesc);

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLista(abertas),
                    _buildLista(finalizadas),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return const Center(child: Text('Nenhuma ocorrência encontrada.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final data = (doc.data() as Map<String, dynamic>? ?? const {});

        final tipo = (data['tipoOcorrencia'] as String?) ?? '';
        final gravidade = (data['gravidade'] as String?) ?? '';
        final relato = (data['relato'] as String?) ?? '';
        final status = (data['status'] as String?) ?? '';
        final createdTs = data['criadoEm'] as Timestamp?;
        final dataLocal = createdTs?.toDate();

        // Guardiões vinculados a esta ocorrência (para SMS)
        final idsGuardioes =
            (data['id_guardiao'] as List?)?.toList() ?? <dynamic>[];

        // ------ LOCAL ------
        final anexosLocais =
            (data['anexosLocais'] as List?)?.cast<String>() ?? const <String>[];

        // ------ URLs de mídias (somente SOS) ------
        final urlsSOS =
            (tipo.toUpperCase() == 'SOS') ? _coletarUrlsDeMidia(data) : const <String>[];

        return Card(
          key: ValueKey(doc.id),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$tipo • $gravidade',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 8),

                if (relato.isNotEmpty)
                  Text(
                    relato,
                    style: const TextStyle(fontSize: 14),
                  ),

                // ------ SOMENTE SOS: cards para mídias da nuvem ------
                if (urlsSOS.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Mídias (nuvem):',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int j = 0; j < urlsSOS.length; j++)
                        InkWell(
                          onTap: () => _abrirUrlNoNavegador(urlsSOS[j]),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 100,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_isImagemUrl(urlsSOS[j]))
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      urlsSOS[j],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(
                                          _iconeParaUrl(urlsSOS[j]),
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Center(
                                    child: Icon(
                                      _iconeParaUrl(urlsSOS[j]),
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                Positioned(
                                  left: 6,
                                  bottom: 4,
                                  right: 6,
                                  child: Text(
                                    'Mídia ${j + 1}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 2,
                                          color: Colors.white,
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                // ------ ANEXOS LOCAIS ------
                if (anexosLocais.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Anexos dessa ocorrência:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: -8,
                    children: [
                      for (int idx = 0; idx < anexosLocais.length; idx++)
                        InputChip(
                          label: Text('Arquivo ${idx + 1}'),
                          backgroundColor: AppColors.primaryLight,
                          onPressed: () => _abrirLocal(anexosLocais[idx]),
                          onDeleted: (status == 'aberto')
                              ? () async {
                                  try {
                                    await _service.removerAnexoLocal(
                                      doc.id,
                                      anexosLocais[idx],
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Anexo removido'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Falha ao remover: $e'),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                Text(
                  dataLocal != null
                      ? 'Registrada em: ${_formatDateTime(dataLocal)}'
                      : 'Registrada em: —',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),

                const Divider(height: 22),

                // === NÃO MOSTRAR HISTÓRICO PARA SOS ===
                if (tipo.toUpperCase() != 'SOS')
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text(
                      'Histórico',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    children: [
                      _HistoricoLocal(ocId: doc.id),
                    ],
                  ),

                const SizedBox(height: 8),

                // Ações
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'aberto') ...[
                      ElevatedButton(
                        onPressed: () async {
                          await _abrirEditorOcorrenciaLocal(
                            context,
                            docId: doc.id,
                            relatoAtual: relato,
                            data: data,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primarySoft,
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Editar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Finalizar ocorrência?'),
                                  content: const Text(
                                    'Após finalizar, não será possível editar.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Finalizar'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                          if (!ok) return;

                          await _service.finalizarOcorrencia(doc.id);

                          // Enviar SMS avisando finalização (best-effort)
                          try {
                            final nomeUsuario = await _obterNomeUsuario();
                            await _enviarSmsFinalizacaoOcorrencia(
                              idsGuardioes: idsGuardioes,
                              nomeUsuario: nomeUsuario,
                              tipo: tipo,
                              gravidade: gravidade,
                            );
                          } catch (e) {
                            debugPrint(
                                'Erro ao enviar SMS de finalização: $e');
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ocorrência finalizada'),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryMedium,
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Finalizar'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------- Editor (LOCAL + STORAGE) --------
  Future<void> _abrirEditorOcorrenciaLocal(
    BuildContext context, {
    required String docId,
    required String relatoAtual,
    required Map<String, dynamic> data,
  }) async {
    final controller = TextEditingController(text: relatoAtual);
    List<PlatformFile> selecionados = [];

    // Dados para SMS
    final tipo = (data['tipoOcorrencia'] as String?) ?? '';
    final gravidade = (data['gravidade'] as String?) ?? '';
    final idsGuardioes =
        (data['id_guardiao'] as List?)?.toList() ?? <dynamic>[];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final String textoAtual = controller.text.trim();
              final bool relatoMudou = textoAtual != relatoAtual.trim();
              final bool anexosAdicionados = selecionados.isNotEmpty;
              final bool houveAlteracao = relatoMudou || anexosAdicionados;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Editar ocorrência',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: controller,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: 'Relato',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),

                  const SizedBox(height: 6),
                  if (!houveAlteracao)
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Nenhuma alteração detectada',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final res = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.any,
                            withData: true,
                            withReadStream: true,
                          );
                          if (res != null && res.files.isNotEmpty) {
                            setModalState(() => selecionados.addAll(res.files));
                          }
                        },
                        child: const Text('Adicionar anexos'),
                      ),
                      const SizedBox(width: 12),
                      Text('Selecionados: ${selecionados.length}'),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final texto = controller.text.trim();
                          if (texto.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('O relato não pode ficar vazio'),
                                ),
                              );
                            }
                            return;
                          }
                          if (!houveAlteracao) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Nenhuma alteração detectada'),
                                ),
                              );
                            }
                            return;
                          }

                          Navigator.pop(ctx); // fecha o modal

                          try {
                            // 1) Salva LOCALMENTE os arquivos escolhidos
                            final novosCaminhosLocais = <String>[];
                            for (final f in selecionados) {
                              final saved = await savePickedFileLocally(
                                f,
                                ocorrenciaId: docId,
                              );
                              novosCaminhosLocais.add(saved);
                            }

                            // 2) Faz UPLOAD para o FIREBASE STORAGE em paralelo
                            final uploadFutures =
                                novosCaminhosLocais.map((localPath) async {
                              try {
                                return await _uploadArquivoParaStorage(
                                  pathLocal: localPath,
                                  uid: _uid,
                                  ocId: docId,
                                );
                              } catch (e) {
                                debugPrint('Falha ao enviar $localPath: $e');
                                return null;
                              }
                            }).toList();

                            final novasUrlsCloud =
                                (await Future.wait(uploadFutures))
                                    .whereType<String>()
                                    .toList();

                            // 3) Atualiza no Firestore (relato + locais + cloud)
                            await _service.editarOcorrenciaHibrido(
                              docId,
                              novoRelato: texto,
                              caminhosNovosLocais: novosCaminhosLocais,
                              urlsNovasCloud: novasUrlsCloud,
                            );

                            // 4) Envia SMS avisando que a ocorrência foi editada (best-effort)
                            try {
                              final nomeUsuario = await _obterNomeUsuario();
                              await _enviarSmsAtualizacaoOcorrencia(
                                idsGuardioes: idsGuardioes,
                                nomeUsuario: nomeUsuario,
                                tipo: tipo,
                                gravidade: gravidade,
                              );
                            } catch (e) {
                              debugPrint(
                                  'Erro ao enviar SMS de atualização: $e');
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ocorrência atualizada'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Falha ao atualizar: $e'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Salvar'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ------- Helpers -------
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _formatDateTime(DateTime dt) {
    final d = _two(dt.day);
    final m = _two(dt.month);
    final y = dt.year.toString();
    final hh = _two(dt.hour);
    final mm = _two(dt.minute);
    return '$d/$m/$y $hh:$mm';
  }

  Future<void> _abrirLocal(String path) async {
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo não encontrado:\n$path')),
        );
      }
      return;
    }
    await OpenFilex.open(path);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final st = status.toLowerCase();
    Color bg;
    Color textColor = Colors.black87;
    String label;

    if (st == 'aberto') {
      bg = AppColors.primarySoft;
      label = 'ABERTO';
    } else if (st == 'finalizado') {
      bg = AppColors.primaryMedium;
      label = 'FINALIZADO';
    } else {
      bg = Colors.grey.shade300;
      label = st.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

/// Histórico que lê o campo `midiasLocais` de cada documento de histórico
class _HistoricoLocal extends StatelessWidget {
  final String ocId;
  const _HistoricoLocal({required this.ocId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ocorrencias')
          .doc(ocId)
          .collection('historico')
          .orderBy('criadoEm', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (snap.hasError) {
          return Text(
            'Erro ao carregar histórico: ${snap.error}',
            style: const TextStyle(color: Colors.red),
          );
        }

        final historicos = snap.data?.docs ?? [];
        if (historicos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Sem histórico registrado.'),
          );
        }

        return Column(
          children: historicos.map((h) {
            final data = (h.data() as Map<String, dynamic>? ?? const {});
            final criadoEm = (data['criadoEm'] as Timestamp?)?.toDate();
            final acao = (data['acao'] as String?) ?? 'criado';

            final titulo =
                criadoEm != null ? _format(criadoEm) : 'Histórico sem data';

            final relatoCriado = (data['relato'] as String?) ?? '';
            final midiasCriado =
                (data['midiasLocais'] as List?)?.cast<String>() ??
                    const <String>[];

            final relatoAnterior = (data['relatoAnterior'] as String?) ?? '';
            final novoRelato = (data['novoRelato'] as String?) ?? '';
            final adicionados =
                (data['adicionadosLocais'] as List?)?.cast<String>() ??
                    const <String>[];
            final removidos =
                (data['removidosLocais'] as List?)?.cast<String>() ??
                    const <String>[];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),

                  if (acao == 'criado') ...[
                    if (relatoCriado.isNotEmpty) Text('Relato: $relatoCriado'),
                    const SizedBox(height: 6),
                    if (midiasCriado.isEmpty)
                      const Text('Sem mídias neste histórico.')
                    else
                      _GridLocais(paths: midiasCriado),
                  ] else ...[
                    if (relatoAnterior.isNotEmpty || novoRelato.isNotEmpty)
                      Text('Relato: $relatoAnterior → $novoRelato'),
                    const SizedBox(height: 6),

                    if (adicionados.isNotEmpty) ...[
                      const Text(
                        'Adicionados nesta edição:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      _GridLocais(paths: adicionados),
                      const SizedBox(height: 6),
                    ],

                    if (removidos.isNotEmpty) ...[
                      const Text(
                        'Removidos nesta edição:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: removidos
                            .map(
                              (p) => InputChip(
                                label: Text(p.split('/').last),
                                onPressed: () => OpenFilex.open(p),
                              ),
                            )
                            .toList(),
                      ),
                    ],

                    if (adicionados.isEmpty &&
                        removidos.isEmpty &&
                        relatoAnterior == novoRelato)
                      const Text('Sem mudanças de mídia nesta edição.'),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _format(DateTime dt) {
    final d = _two(dt.day);
    final m = _two(dt.month);
    final y = dt.year.toString();
    final hh = _two(dt.hour);
    final mm = _two(dt.minute);
    return 'Histórico de $d/$m/$y $hh:$mm';
  }
}

/// Grid simples que tenta mostrar imagem se for imagem, senão ícone + abrir com OpenFilex
class _GridLocais extends StatelessWidget {
  final List<String> paths;
  const _GridLocais({required this.paths});

  bool _isImage(String p) {
    final lower = p.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.webp');
  }

  IconData _iconFor(String p) {
    final lower = p.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi')) return Icons.play_circle_fill;
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac')) return Icons.audiotrack;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: paths.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final path = paths[i];
        if (_isImage(path) && File(path).existsSync()) {
          return GestureDetector(
            onTap: () => OpenFilex.open(path),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          );
        }
        return InkWell(
          onTap: () => OpenFilex.open(path),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFor(path), size: 32, color: Colors.grey.shade800),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(
                    path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
