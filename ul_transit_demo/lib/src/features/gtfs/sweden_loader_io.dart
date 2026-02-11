import 'dart:io';

Future<String?> loadSwedenStopsFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}
