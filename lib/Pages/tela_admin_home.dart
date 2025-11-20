import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'tela_config.dart'; // Caso ainda use em outro lugar
import 'tela_tipo_ocorrencia.dart';
import 'tela_login.dart';
import 'tela_usuario.dart';
import 'tela_enviar_email.dart';
import 'tela_textoEmails.dart';
import 'tela_configuracoes.dart';
import 'tela_ocorrencia.dart';
import 'tela_localizacao.dart';
import 'tela_sos.dart';
import 'tela_registrar_ocorrencia.dart';
import 'perfil_usuario_e_guardiao.dart';

class TelaAdminHome extends StatefulWidget {
  const TelaAdminHome({super.key});

  @override
  State<TelaAdminHome> createState() => _TelaAdminHomeState();
}

class _TelaAdminHomeState extends State<TelaAdminHome> {
  // Controllers para configuração do SOS
  final _photoMinutesController = TextEditingController();
  final _audioMinutesController = TextEditingController();

  bool _carregandoConfigSos = true;
  bool _salvandoConfigSos = false;

  @override
  void initState() {
    super.initState();
    _carregarConfigSos();
  }

  @override
  void dispose() {
    _photoMinutesController.dispose();
    _audioMinutesController.dispose();
    super.dispose();
  }

  // ==== Logout ====
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TelaLogin()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao deslogar: $e')),
      );
    }
  }

  // ==== Configuração SOS (Firestore) ====

  Future<void> _carregarConfigSos() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('sos_media')
          .get();

      final data = doc.data() ?? {};

      final photoSec =
          (data['photoIntervalSeconds'] as num?)?.toInt() ?? 60;
      final audioSec =
          (data['audioDurationSeconds'] as num?)?.toInt() ?? 60;

      _photoMinutesController.text = (photoSec ~/ 60).toString();
      _audioMinutesController.text = (audioSec ~/ 60).toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar config do SOS: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _carregandoConfigSos = false);
      }
    }
  }

  Future<void> _salvarConfigSos() async {
    final photoMin = int.tryParse(_photoMinutesController.text.trim());
    final audioMin = int.tryParse(_audioMinutesController.text.trim());

    if (photoMin == null || audioMin == null || photoMin <= 0 || audioMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe minutos válidos (número inteiro > 0).'),
        ),
      );
      return;
    }

    setState(() => _salvandoConfigSos = true);

    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('sos_media')
          .set({
        'photoIntervalSeconds': photoMin * 60,
        'audioDurationSeconds': audioMin * 60,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações do SOS salvas com sucesso!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar config do SOS: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvandoConfigSos = false);
      }
    }
  }

  // ==== Cards ====

  Widget _buildCardConfigSos() {
    if (_carregandoConfigSos) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configurações do SOS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Defina o intervalo entre fotos e a duração da gravação de áudio '
              'após o acionamento do botão SOS.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _photoMinutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Intervalo entre fotos (minutos)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _audioMinutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duração do áudio (minutos)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvandoConfigSos ? null : _salvarConfigSos,
                child: _salvandoConfigSos
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar configurações'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String titulo,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(height: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  // ==== UI Principal ====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Administrador'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card de configuração do SOS
                    _buildCardConfigSos(),
                    const SizedBox(height: 24),

                    // Seção: Usuários e Guardiões
                    _buildSectionCard(
                      titulo: 'Usuários e Guardiões',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_add_alt),
                          title: const Text('Cadastrar usuário'),
                          subtitle: const Text('Criar novos perfis de acesso'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TelaUsuario(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: const Text('Cadastro de Guardião'),
                          subtitle:
                              const Text('Gerenciar responsáveis e vínculos'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PerfilGuardiaoScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Seção: Ocorrências e monitoramento
                    _buildSectionCard(
                      titulo: 'Ocorrências e monitoramento',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: const Text('Registrar ocorrência'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const OcorrenciaPage(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: const Text('Minhas ocorrências'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OcorrenciasPage(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: const Text('Localização da vítima'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GuardianMapPage(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.warning_amber_rounded),
                          title: const Text('Simular SOS'),
                          subtitle: const Text('Fluxo de teste do SOS'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TelaVitimaSOS(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.list_alt_outlined),
                          title: const Text('Tipos de ocorrência'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TipoOcorrencia(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Seção: Comunicação por e-mail
                    _buildSectionCard(
                      titulo: 'Comunicação por e-mail',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.send_outlined),
                          title: const Text('Enviar e-mail'),
                          subtitle:
                              const Text('Disparar mensagens para usuários'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EnviarEmailPage(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: const Text('Textos de e-mail'),
                          subtitle: const Text('Modelos de mensagens'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TelaTextoEmails(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Seção: Configurações gerais
                    _buildSectionCard(
                      titulo: 'Configurações do sistema',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Configurações'),
                          subtitle: const Text('Ajustes avançados do sistema'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SettingsMenuScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Botão de Logout
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'Sair do painel',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
