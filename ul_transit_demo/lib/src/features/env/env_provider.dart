import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loads a local `.env` file from the app working directory (if present)
/// and exposes its key/value pairs as a `Map<String,String>`.
final envFileProvider = FutureProvider<Map<String, String>>((ref) async {
  // Look for a .env file in the working directory or its parent (repo root).
  final candidates = [File('.env'), File('../.env')];
  File? file;
  for (final c in candidates) {
    if (await c.exists()) {
      file = c;
      break;
    }
  }
  if (file == null) return <String, String>{};
  final content = await file.readAsString();
  final lines = content.split(RegExp(r'\r?\n'));
  final map = <String, String>{};
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    var val = line.substring(idx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.substring(1, val.length - 1);
    }
    map[key] = val;
  }
  return map;
});
