import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

/// Copia o PlatformFile para a pasta do app e retorna o caminho salvo.
/// Se quiser, passe [ocorrenciaId] para organizar por ocorrência.
Future<String> savePickedFileLocally(PlatformFile f, {String? ocorrenciaId}) async {
  final Directory appDir = await getApplicationDocumentsDirectory();
  final base = Directory('${appDir.path}/midias${ocorrenciaId != null ? '/$ocorrenciaId' : ''}');
  if (!await base.exists()) await base.create(recursive: true);

  // nome único para evitar conflito
  final ts = DateTime.now().millisecondsSinceEpoch;
  final safeName = (f.name).replaceAll(RegExp(r'[^\w\.\-]'), '_');
  final filePath = '${base.path}/$ts\_$safeName';
  final outFile = File(filePath);

  if (f.path != null) {
    await File(f.path!).copy(outFile.path);
  } else if (f.bytes != null) {
    await outFile.writeAsBytes(f.bytes!, flush: true);
  } else if (f.readStream != null) {
    final bb = BytesBuilder();
    await for (final chunk in f.readStream!) {
      bb.add(chunk);
    }
    await outFile.writeAsBytes(bb.toBytes(), flush: true);
  } else {
    throw Exception('Arquivo sem dados para salvar localmente.');
  }

  return outFile.path; // guarde isso no Firestore em 'anexosLocais'
}
