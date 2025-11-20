import 'package:flutter/material.dart';
import 'perfil_usuario_e_guardiao.dart'; // Certifique-se de que o caminho esteja correto

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
      ),
      body: ListView(
        children: [
          // Tela de Cadastro de Guardião
          ListTile(
            leading: const Icon(Icons.shield),
            title: const Text('Cadastro de Guardião'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PerfilGuardiaoScreen()), // Navega para a tela de cadastro de guardião
              );
            },
          ),
          // Você pode adicionar mais opções aqui, por exemplo:
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Outras Configurações'),
            onTap: () {
              // Aqui você pode redirecionar para outras configurações ou funcionalidades, caso tenha
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Em breve mais opções.')),
              );
            },
          ),
        ],
      ),
    );
  }
}
