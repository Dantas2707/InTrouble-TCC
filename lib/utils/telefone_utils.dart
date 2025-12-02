class TelefoneUtils {
  static String normalizarTelefoneBR(String input) {
    // remove tudo que não for dígito
    final digits = input.replaceAll(RegExp(r'\D'), '');

    // se já vier com DDI 55 e tiver pelo menos 12 dígitos, só garante o +
    // ex: 5561984250137 -> +5561984250137
    if (digits.startsWith('55') && digits.length >= 12) {
      return '+$digits';
    }

    // se vier apenas com DDD + número, ex: 61984250137
    if (digits.length >= 10 && !digits.startsWith('55')) {
      return '+55$digits';
    }

    // fallback: devolve apenas com +
    return '+$digits';
  }
}
