import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;

/// Cross-platform file save that works on both mobile and desktop.
/// file_picker v8.x ignores `bytes` on desktop — this helper writes manually.
Future<String?> saveFileWithBytes({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
  FileType type = FileType.custom,
  List<String>? allowedExtensions,
}) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  if (savePath == null) return null;

  // On desktop, file_picker v8.x doesn't write bytes — do it manually.
  // On mobile (Android/iOS), file_picker handles bytes correctly via SAF.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    final file = File(savePath);
    await file.writeAsBytes(bytes);
  }

  return savePath;
}
