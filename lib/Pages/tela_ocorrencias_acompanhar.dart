import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore.dart';
import 'tela_detalhe_ocorrencia_guardiao.dart';

// Cores da paleta
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kRosaClaro = Color(0xFFF2C4CD); // #F2C4CD
const kRosaMedio = Color(0xFFD9B4BB); // #D9B4BB
const kRosaSuave = Color(0xFFF2C4C4); // #F2C4C4
const kCinzaClaro = Color(0xFFF2F2F2); // #F2F2F2

class TelaOcorrenciasAcompanhar extends StatefulWidget {
  const TelaOcorrenciasAcompanhar({super.key});

  @override
  State<TelaOcorrenciasAcompanhar> createState() =>
      _TelaOcorrenciasAcompanharState();
}

class _TelaOcorrenciasAcompanharState
    extends State<TelaOcorrenciasAcompanhar> {
  final FirestoreService _service = FirestoreService();

  /// 'todos', 'aberto', 'finalizado'
  String _statusSelecionado = 'todos';

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'aberto':
        return kRosaMedio;
      case 'finalizado':
        return kCinzaClaro;
      default:
        return kRosaClaro;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'aberto':
        return 'Aberto';
      case 'finalizado':
        return 'Finalizado';
      default:
        return status.isEmpty ? 'Sem status' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Usuário não autenticado.'),
        ),
      );
    }

    final stream = _service.getOcorrenciasDoGuardiaoStream(
      user.uid,
      status: _statusSelecionado == 'todos' ? null : _statusSelecionado,
    );

    return Scaffold(
      // AppBar com degradê
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Ocorrências que acompanho',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kRosaClaro, kRosaMedio],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      // Fundo com gradient suave
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kCinzaClaro, kRosaMuitoClaro],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título / subtítulo da tela
                const Text(
                  'Acompanhe em tempo real\nas ocorrências das vítimas que você guarda.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 120, 96, 102),
                  ),
                ),
                const SizedBox(height: 16),

                // Card de filtro
                Card(
                  color: kCinzaClaro,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          color: kRosaMedio,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Filtrar por status:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color.fromARGB(255, 120, 96, 102),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _statusSelecionado,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(16),
                              dropdownColor: Colors.white,
                              items: const [
                                DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'aberto',
                                  child: Text('Abertos'),
                                ),
                                DropdownMenuItem(
                                  value: 'finalizado',
                                  child: Text('Finalizados'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _statusSelecionado = value;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Lista de ocorrências
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: stream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: kRosaMedio,
                          ),
                        );
                      }

                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Erro ao carregar: ${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }

                      final docs = snap.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: kRosaMedio,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Você ainda não está acompanhando\nnenhuma ocorrência nesse filtro.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color.fromARGB(255, 120, 96, 102),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;

                          final tipo =
                              (data['tipoOcorrencia'] ?? '').toString();
                          final gravidade =
                              (data['gravidade'] ?? '').toString();
                          final status = (data['status'] ?? '').toString();
                          final criadoEm =
                              (data['criadoEm'] as Timestamp?)?.toDate();
                          final ownerUid =
                              (data['ownerUid'] ?? '').toString();

                          return FutureBuilder<DocumentSnapshot>(
                            future: ownerUid.isNotEmpty
                                ? FirebaseFirestore.instance
                                    .collection('usuario')
                                    .doc(ownerUid)
                                    .get()
                                : Future.value(null),
                            builder: (context, userSnap) {
                              String nomeVitima = '';

                              if (userSnap.hasData &&
                                  userSnap.data != null &&
                                  userSnap.data!.exists) {
                                final uData = userSnap.data!.data()
                                    as Map<String, dynamic>?;
                                nomeVitima =
                                    (uData?['nome'] ?? '').toString();
                              }

                              final statusColor = _statusColor(status);

                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TelaDetalheOcorrenciaGuardiao(
                                        ocorrenciaId: doc.id,
                                        dadosOcorrencia: data,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Barrinha colorida do status
                                      Container(
                                        width: 6,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(18),
                                            bottomLeft: Radius.circular(18),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Tipo de ocorrência + chip de status
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      tipo.isEmpty
                                                          ? 'Ocorrência sem tipo'
                                                          : tipo,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                        color: Color.fromARGB(
                                                            255, 82, 60, 66),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Chip(
                                                    label: Text(
                                                      _statusLabel(status),
                                                    ),
                                                    labelStyle:
                                                        const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    backgroundColor:
                                                        statusColor
                                                            .withOpacity(0.3),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              if (nomeVitima.isNotEmpty)
                                                Text(
                                                  'Vítima: $nomeVitima',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color.fromARGB(
                                                        255, 120, 96, 102),
                                                  ),
                                                ),
                                              if (nomeVitima.isNotEmpty)
                                                const SizedBox(height: 2),
                                              Text(
                                                'Gravidade: $gravidade',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color.fromARGB(
                                                      255, 120, 96, 102),
                                                ),
                                              ),
                                              if (criadoEm != null)
                                                const SizedBox(height: 2),
                                              if (criadoEm != null)
                                                Text(
                                                  'Criado em: ${_formatDataHora(criadoEm)}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color.fromARGB(
                                                        255, 140, 114, 120),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Padding(
                                        padding:
                                            EdgeInsets.only(right: 8.0),
                                        child: Icon(
                                          Icons.chevron_right,
                                          color: Color.fromARGB(
                                              255, 140, 114, 120),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDataHora(DateTime dateTime) {
    // Formato simples dd/MM/yyyy HH:mm
    final dia = dateTime.day.toString().padLeft(2, '0');
    final mes = dateTime.month.toString().padLeft(2, '0');
    final ano = dateTime.year.toString();
    final hora = dateTime.hour.toString().padLeft(2, '0');
    final min = dateTime.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano $hora:$min';
  }
}
