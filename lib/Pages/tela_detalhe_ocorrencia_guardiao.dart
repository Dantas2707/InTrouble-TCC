import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crud/theme/app_colors.dart';
import 'package:intl/intl.dart';

class TelaDetalheOcorrenciaGuardiao extends StatelessWidget {
  final String ocorrenciaId;
  final Map<String, dynamic> dadosOcorrencia;

  const TelaDetalheOcorrenciaGuardiao({
    super.key,
    required this.ocorrenciaId,
    required this.dadosOcorrencia,
  });

  // Ajuste: formatando data de criação sem milissegundos
  String _formatarDataHora(DateTime? data) {
    if (data == null) return 'Data indisponível';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(data);
  }

  // Abre URL (foto, áudio, vídeo, PDF etc.) no app externo / navegador
  Future<void> _abrirUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir URL: $e');
    }
  }

  bool _ehImagem(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  IconData _iconePorExtensao(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v')) {
      return Icons.videocam;
    } else if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a')) {
      return Icons.audiotrack;
    } else if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    }
    return Icons.attach_file;
  }

     Widget _buildMiniAnexo(String url) {
    final isImage = _ehImagem(url);
    if (isImage) {
      return GestureDetector(
        onTap: () => _abrirUrl(url),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
        ),
      );
    } else {
      // ainda uso o nome só pra descobrir o ícone certo
      final fileName = url.split('?').first.split('/').last;
      final icon = _iconePorExtensao(fileName);

      return GestureDetector(
        onTap: () => _abrirUrl(url),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20), // usa o ícone certo
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'arquivo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stream do DOC da ocorrência (pra atualizar anexos / status / relato em tempo real)
    final ocorrenciaStream = FirebaseFirestore.instance
        .collection('ocorrencias')
        .doc(ocorrenciaId)
        .snapshots();

    // Stream do histórico
    final historicoStream = FirebaseFirestore.instance
        .collection('ocorrencias')
        .doc(ocorrenciaId)
        .collection('historico')
        .orderBy('criadoEm', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da ocorrência'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ================= CABEÇALHO + ANEXOS (DOC DA OCORRÊNCIA) =================
          StreamBuilder<DocumentSnapshot>(
            stream: ocorrenciaStream,
            builder: (context, snap) {
              Map<String, dynamic> data = dadosOcorrencia;

              if (snap.hasData && snap.data != null && snap.data!.exists) {
                data = snap.data!.data() as Map<String, dynamic>;
              }

              final tipo = (data['tipoOcorrencia'] ?? '').toString();
              final gravidade = (data['gravidade'] ?? '').toString();
              final status = (data['status'] ?? '').toString();
              final relato = (data['relato'] ?? '').toString();
              final textoSocorro =
                  (data['textoSocorro'] ?? '').toString();
              final criadoEm =
                  (data['criadoEm'] as Timestamp?)?.toDate();
              final anexos =
                  (data['anexos'] as List?)?.cast<String>() ?? <String>[];

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card com info principal
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tipo.isEmpty ? 'Sem tipo' : tipo,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Gravidade: $gravidade'),
                            Text('Status: $status'),
                            if (criadoEm != null)
                              Text('Criado em: ${_formatarDataHora(criadoEm)}'),
                            const SizedBox(height: 12),
                            if (relato.isNotEmpty) ...[
                              const Text(
                                'Relato da vítima:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(relato),
                            ],
                            const SizedBox(height: 8),
                            if (textoSocorro.isNotEmpty) ...[
                              const Text(
                                'Texto de socorro:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(textoSocorro),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ================= ANEXOS GERAIS DA OCORRÊNCIA =================
                    if (anexos.isNotEmpty) ...[
                      const Text(
                        'Anexos da ocorrência',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: anexos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final url = anexos[index];
                            return _buildMiniAnexo(url);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Toque em um anexo para abrir.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Histórico da ocorrência',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // ================= HISTÓRICO =================
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: historicoStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar histórico: ${snap.error}',
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Ainda não há atualizações registradas para esta ocorrência.',
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data =
                        docs[index].data() as Map<String, dynamic>;

                    final acao = (data['acao'] ?? '').toString();
                    final relatoAnterior =
                        (data['relatoAnterior'] ?? '').toString();
                    final novoRelato =
                        (data['novoRelato'] ?? '').toString();
                    final criadoEmHist =
                        (data['criadoEm'] as Timestamp?)?.toDate();

                    final midiasCloud =
                        (data['midiasCloud'] as List?)
                                ?.cast<String>() ??
                            <String>[];
                    final adicionadosCloud =
                        (data['adicionadosCloud'] as List?)
                                ?.cast<String>() ??
                            <String>[];
                    final anexosHistorico = <String>[
                      ...midiasCloud,
                      ...adicionadosCloud,
                    ];

                    String descricao = '';
                    if (acao == 'criado') {
                      descricao = 'Ocorrência criada.';
                    } else if (acao == 'edicao' ||
                        acao == 'editado') {
                      descricao = 'Relato editado.';
                    } else if (acao == 'remocao_local') {
                      descricao = 'Anexo local removido.';
                    } else {
                      descricao = acao;
                    }

                    return ListTile(
                      title: Text(descricao),
                      subtitle: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          if (relatoAnterior.isNotEmpty)
                            Text(
                              'Relato anterior: $relatoAnterior',
                            ),
                          if (novoRelato.isNotEmpty)
                            Text(
                              'Novo relato: $novoRelato',
                            ),
                          if (criadoEmHist != null)
                            Text('Em: ${_formatarDataHora(criadoEmHist)}'),

                          // ====== ANEXOS ESPECÍFICOS DESTE ITEM DO HISTÓRICO ======
                          if (anexosHistorico.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Anexos desta atualização:',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 90,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: anexosHistorico.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (context, i) {
                                  final url =
                                      anexosHistorico[i];
                                  return _buildMiniAnexo(url);
                                },
                              ),
                            ),
                          ],
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
    );
  }
}
