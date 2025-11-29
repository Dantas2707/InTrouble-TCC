import 'dart:io';
import 'package:crud/services/firestore.dart';
import 'package:crud/services/local_media.dart';
import 'package:crud/services/sms_service.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crud/theme/app_colors.dart';

class OcorrenciaPage extends StatefulWidget {
  const OcorrenciaPage({super.key});

  @override
  State<OcorrenciaPage> createState() => _OcorrenciaPageState();
}

class _OcorrenciaPageState extends State<OcorrenciaPage> {
  final FirestoreService _service = FirestoreService();

  final _relatoCtrl = TextEditingController();
  final _textoSocorroCtrl = TextEditingController(
    text: 'Uma ocorrência está em aberto. Preciso de ajuda!',
  );

  String? _tipoSelecionado;
  String? _gravidadeSelecionada;

  static const List<String> _gravidadesFixas = [
    'Baixo',
    'Médio',
    'Grave',
  ];

  // Guarda caminhos locais
  final List<String> _anexosLocais = [];

  // IDs dos guardiões selecionados
  List<String> _guardioesSelecionados = [];

  bool _isPicking = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _relatoCtrl.dispose();
    _textoSocorroCtrl.dispose();
    super.dispose();
  }

  // ------------ UI helpers ------------

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.primary),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.primaryMedium, width: 1.6),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    Color? background,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background ?? AppColors.primary,
          foregroundColor: Colors.black87,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  // ------------ Anexos ------------

  Future<void> _pickAnexos() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
        withReadStream: true,
      );
      if (res == null || res.files.isEmpty) return;

      const maxBytes = 100 * 1024 * 1024; // 100MB
      const allowedExts = <String>{
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'mp4',
        'mov',
        'm4v',
        'mp3',
        'wav',
        'aac',
        'pdf',
        'doc',
        'docx'
      };

      int salvos = 0;
      for (final f in res.files) {
        final size = f.bytes?.length ?? f.size;
        final ext = (f.extension ?? '').toLowerCase();

        if (size > maxBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Arquivo muito grande: ${f.name} (máx 100MB)'),
            ),
          );
          continue;
        }
        if (ext.isEmpty || !allowedExts.contains(ext)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tipo não permitido: ${f.name}')),
          );
          continue;
        }

        try {
          final savedPath = await savePickedFileLocally(f);
          _anexosLocais.add(savedPath);
          salvos++;
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha ao salvar ${f.name}: $e')),
          );
        }
      }

      if (salvos > 0 && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Anexos adicionados: $salvos')),
        );
      }
    } catch (e, s) {
      debugPrint('pick error: $e\n$s');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao anexar: $e')),
      );
    } finally {
      _isPicking = false;
    }
  }

  // =========================================================
  //      HELPER: CAPTURAR LOCALIZAÇÃO UMA ÚNICA VEZ
  // =========================================================

  Future<Position?> _obterLocalizacaoAtual() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Serviço de localização desativado.');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Permissão de localização negada pelo usuário.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Permissão de localização negada permanentemente.');
      return null;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return pos;
    } catch (e) {
      debugPrint('Erro ao obter localização: $e');
      return null;
    }
  }

  // =========================================================
  //      HELPER: BUSCAR TELEFONES DOS GUARDIÕES SELECIONADOS
  // =========================================================

  Future<List<String>> _obterTelefonesGuardioesSelecionados() async {
    if (_guardioesSelecionados.isEmpty) return [];

    final List<String> telefones = [];

    for (final idGuardiao in _guardioesSelecionados) {
      try {
        final guardiaoDoc = await FirebaseFirestore.instance
            .collection('usuario')
            .doc(idGuardiao)
            .get();

        if (!guardiaoDoc.exists || guardiaoDoc.data() == null) {
          debugPrint("Guardião não encontrado: $idGuardiao");
          continue;
        }

        final data = guardiaoDoc.data() as Map<String, dynamic>;
        final phoneRaw = (data['numerotelefone'] ?? '').toString().trim();

        if (phoneRaw.isEmpty) {
          debugPrint(
            "Número de telefone não encontrado para o guardião: $idGuardiao",
          );
          continue;
        }

        telefones.add(phoneRaw);
      } catch (e) {
        debugPrint("Erro ao processar guardião $idGuardiao: $e");
      }
    }

    return telefones;
  }

  // ------------ Registrar ocorrência ------------

  Future<void> _registrarOcorrencia() async {
    if (_isSaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado')),
      );
      return;
    }

    if (_tipoSelecionado == null || _gravidadeSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione tipo e gravidade')),
      );
      return;
    }

    final relato = _relatoCtrl.text.trim();
    final textoSocorro = _textoSocorroCtrl.text.trim();

    if (relato.isEmpty || textoSocorro.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos')),
      );
      return;
    }

    _isSaving = true;
    setState(() {});
    try {
      // ================================
      // Buscar nome do usuário no Firestore
      // ================================
      String nomeUsuario = 'Usuário';

      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuario')
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          nomeUsuario = (data['nome'] ?? nomeUsuario).toString();
        }
      } catch (e) {
        debugPrint('Erro ao buscar nome do usuário: $e');
      }

      // ================================
      // Capturar data/hora e localização UMA VEZ
      // ================================
      final DateTime agora = DateTime.now();
      Position? posicao;
      try {
        posicao = await _obterLocalizacaoAtual();
      } catch (e) {
        debugPrint('Erro ao capturar localização: $e');
      }

      final double? latitude = posicao?.latitude;
      final double? longitude = posicao?.longitude;

      // ================================
      // Salva a ocorrência no Firestore
      // (ocorrência NORMAL → isSos: false)
      // ================================
      await _service.addOcorrencia(
        _tipoSelecionado!,
        _gravidadeSelecionada!,
        relato.toLowerCase(),
        textoSocorro,
        false, // enviarParaGuardiao (controle via SMS + idGuardiao)
        anexosLocais: _anexosLocais,
        idGuardiao:
            _guardioesSelecionados.isEmpty ? [] : _guardioesSelecionados,
        ownerUid: user.uid,
        // NOVOS CAMPOS
        isSos: false,
        latitudeInicial: latitude,
        longitudeInicial: longitude,
        dataHoraAbertura: agora,
      );

      // ================================
      // Enviar SMS via SmsService (Ocorrência criada)
      // ================================
      if (_guardioesSelecionados.isNotEmpty) {
        final telefonesGuardioes =
            await _obterTelefonesGuardioesSelecionados();

        if (telefonesGuardioes.isNotEmpty) {
          final tipoComGravidade = _gravidadeSelecionada != null &&
                  _gravidadeSelecionada!.isNotEmpty
              ? '$_tipoSelecionado (Gravidade: $_gravidadeSelecionada)'
              : _tipoSelecionado!;

          await SmsService.instance.smsOcorrenciaCriada(
            telefonesGuardioes: telefonesGuardioes,
            nomeVitima: nomeUsuario,
            tipoOcorrencia: tipoComGravidade,
          );
        } else {
          debugPrint(
            '[SMS] Nenhum telefone válido encontrado para os guardiões selecionados.',
          );
        }
      }

      // Reset dos campos
      _relatoCtrl.clear();
      _textoSocorroCtrl.text =
          'Uma ocorrência está em aberto. Preciso de ajuda!'; // mantém padrão desta tela
      setState(() {
        _tipoSelecionado = null;
        _gravidadeSelecionada = null;
        _anexosLocais.clear();
        _guardioesSelecionados.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocorrência registrada com sucesso')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao registrar: $e')),
      );
    } finally {
      _isSaving = false;
      if (mounted) setState(() {});
    }
  }

  // ------------ Selecionar guardiões ------------

  Future<void> _selecionarGuards() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint("Usuário não autenticado.");
      return;
    }

    final guardioesSnapshot = await FirebaseFirestore.instance
        .collection('guardiões')
        .where('status', isEqualTo: 'aceito')
        .where('id_usuario', isEqualTo: uid)
        .get();

    if (guardioesSnapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não possui nenhum guardião registrado.'),
        ),
      );
      return;
    }

    List<String> guardioesIds = [];
    List<String> guardioesNomes = [];

    for (var doc in guardioesSnapshot.docs) {
      final idGuardiao = doc['id_guardiao'];

      final guardiaoDoc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(idGuardiao)
          .get();

      if (guardiaoDoc.exists) {
        guardioesIds.add(idGuardiao);
        guardioesNomes.add(guardiaoDoc['nome']);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Selecione os guardiões'),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ListView.builder(
                  itemCount: guardioesNomes.length,
                  itemBuilder: (context, index) {
                    final id = guardioesIds[index];
                    final nome = guardioesNomes[index];

                    return CheckboxListTile(
                      title: Text(nome),
                      value: _guardioesSelecionados.contains(id),
                      onChanged: (isSelected) {
                        setStateDialog(() {
                          if (isSelected == true) {
                            _guardioesSelecionados.add(id);
                          } else {
                            _guardioesSelecionados.remove(id);
                          }
                        });
                      },
                      activeColor: AppColors.primary,
                    );
                  },
                ),
              ),
              actions: [
                Column(
                  children: [
                    const SizedBox(height: 8),
                    if (_guardioesSelecionados.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Guardião(s) selecionado(s): ${_guardioesSelecionados.length}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {});
                      },
                      child: const Text(
                        'Fechar',
                        style: TextStyle(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ------------ build ------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        title: const Text(
          'Registrar ocorrência',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
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
                      'Nova ocorrência',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Preencha os detalhes do que está acontecendo. '
                      'Você pode anexar mídias e escolher quais guardiões serão avisados.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Card do formulário
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle('Informações da ocorrência'),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: _service.getTipoOcorrenciaStream(),
                      builder: (ctx, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Text(
                            'Erro ao carregar tipos: ${snap.error}',
                            style: const TextStyle(color: Colors.red),
                          );
                        }

                        final docs = snap.data?.docs ?? [];
                        final tipos = docs
                            .map((d) =>
                                ((d.data() as Map<String, dynamic>? ?? {})[
                                            'tipoOcorrencia'] ??
                                        '')
                                    .toString())
                            .where((t) => t.isNotEmpty)
                            .toList();

                        if (tipos.isEmpty) {
                          return const Text(
                            'Nenhum tipo de ocorrência encontrado.',
                            style: TextStyle(color: Colors.red),
                          );
                        }

                        return DropdownButtonFormField<String>(
                          decoration: _inputDecoration('Tipo de ocorrência'),
                          value: _tipoSelecionado,
                          items: tipos
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _tipoSelecionado = v),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Gravidade'),
                      value: _gravidadeSelecionada,
                      items: _gravidadesFixas
                          .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(g),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _gravidadeSelecionada = v),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Relato'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _relatoCtrl,
                      maxLines: 3,
                      decoration: _inputDecoration('Descreva o que aconteceu'),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Texto de socorro'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _textoSocorroCtrl,
                      maxLines: 3,
                      maxLength: 255,
                      decoration: _inputDecoration(
                        'Mensagem enviada aos guardiões',
                      ),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle('Guardiões'),
                    const SizedBox(height: 8),
                    _primaryButton(
                      label: 'Selecionar guardiões',
                      icon: Icons.group_outlined,
                      background: AppColors.primaryLight,
                      onPressed: _selecionarGuards,
                    ),
                    if (_guardioesSelecionados.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selecionados: ${_guardioesSelecionados.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),

                    _sectionTitle('Anexos'),
                    const SizedBox(height: 8),
                    _primaryButton(
                      label: 'Anexar mídia',
                      icon: Icons.attach_file,
                      background: AppColors.primarySoft,
                      onPressed: _isSaving ? null : _pickAnexos,
                    ),
                    if (_anexosLocais.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Arquivos selecionados:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: [
                          for (int i = 0; i < _anexosLocais.length; i++)
                            InputChip(
                              label: Text(
                                File(_anexosLocais[i])
                                    .path
                                    .split('/')
                                    .last,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_anexosLocais[i]),
                                  ),
                                );
                              },
                              onDeleted: _isSaving
                                  ? null
                                  : () => setState(
                                        () => _anexosLocais.removeAt(i),
                                      ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isSaving ? null : _registrarOcorrencia,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryMedium,
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Registrar ocorrência',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}