// lib/services/sms_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class SmsService {
  SmsService._internal();
  static final SmsService instance = SmsService._internal();

  /// Envia SMS abrindo o app de mensagens do celular.
  /// Se houver mais de um telefone, tenta abrir um SMS em grupo.
  Future<void> enviarSmsParaTelefones({
    required List<String> telefones,
    required String mensagem,
  }) async {
    if (telefones.isEmpty) {
      debugPrint('[SMS] Nenhum telefone informado. Abortando envio.');
      return;
    }

    // Normaliza + remove duplicados + remove vazios
    final normalizados = telefones
        .map(_normalizarNumero)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    if (normalizados.isEmpty) {
      debugPrint(
          '[SMS] Todos os telefones ficaram inválidos após normalização.');
      return;
    }

    // Em alguns dispositivos:
    // - Android costuma usar ';' entre números
    // - iOS costuma usar ',' entre números
    final separador = Platform.isIOS ? ',' : ';';
    final destino = normalizados.join(separador);

    final uri = Uri(
      scheme: 'sms',
      path: destino,
      queryParameters: {
        'body': mensagem,
      },
    );

    debugPrint('[SMS] Abrindo app de SMS para: $destino');
    debugPrint('[SMS] Mensagem: $mensagem');

    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        debugPrint('[SMS] Falha ao abrir app de SMS para $destino');
      }
    } catch (e, s) {
      debugPrint('[SMS] Erro ao abrir app de SMS: $e');
      debugPrint('[SMS] STACK: $s');
    }
  }

  /// Normaliza o número (ex: adiciona +55 se precisar)
  String _normalizarNumero(String telefone) {
    var t = telefone.trim();
    if (t.isEmpty) return '';

    // remove espaços e traços
    t = t.replaceAll(RegExp(r'[\s\-]'), '');

    // Se já começar com +, deixo como está
    if (t.startsWith('+')) return t;

    // Se tiver só DDD + número (ex: 6199...), adiciono +55
    if (t.length >= 10 && !t.startsWith('0')) {
      return '+55$t';
    }

    // Último caso: retorno como veio, mas logando
    debugPrint('[SMS] Número não normalizado automaticamente: $telefone');
    return t;
  }

  // ================== Helpers específicos do InTrouble ==================

  Future<void> smsOcorrenciaCriada({
    required List<String> telefonesGuardioes,
    required String nomeVitima,
    required String tipoOcorrencia,
  }) async {
    final msg =
        '⚠️ Alerta InTrouble\n'
        '$nomeVitima acabou de registrar uma ocorrência do tipo: $tipoOcorrencia.\n'
        'Acesse o app para mais detalhes.';

    await enviarSmsParaTelefones(
      telefones: telefonesGuardioes,
      mensagem: msg,
    );
  }

  Future<void> smsOcorrenciaEditada({
    required List<String> telefonesGuardioes,
    required String nomeVitima,
    required String tipoOcorrencia,
  }) async {
    final msg =
        '✏️ Atualização de ocorrência InTrouble\n'
        '$nomeVitima atualizou uma ocorrência do tipo: $tipoOcorrencia.\n'
        'Verifique as novas informações no app.';

    await enviarSmsParaTelefones(
      telefones: telefonesGuardioes,
      mensagem: msg,
    );
  }

  Future<void> smsOcorrenciaFinalizada({
    required List<String> telefonesGuardioes,
    required String nomeVitima,
    required String tipoOcorrencia,
  }) async {
    final msg =
        '✅ Ocorrência finalizada - InTrouble\n'
        '$nomeVitima finalizou uma ocorrência do tipo: $tipoOcorrencia.\n'
        'Caso necessário, confirme se está tudo bem.';

    await enviarSmsParaTelefones(
      telefones: telefonesGuardioes,
      mensagem: msg,
    );
  }

  /// Helper para SOS (se quiser usar também aqui)
  Future<void> smsSos({
    required List<String> telefonesGuardioes,
    required String nomeVitima,
  }) async {
    const gravidade = 'Gravíssima';
    final msg =
        '🚨 SOS InTrouble\n'
        '$nomeVitima acionou o SOS.\n'
        'Gravidade: $gravidade.\n'
        'Abra o app InTrouble para ver a localização e os detalhes.';

    await enviarSmsParaTelefones(
      telefones: telefonesGuardioes,
      mensagem: msg,
    );
  }
}
