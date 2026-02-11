import 'dart:async';
import 'dart:html' as html;

Future<String?> loadSwedenStopsFile(String path) async {
  try {
    final text = await html.HttpRequest.getString(path);
    return text;
  } catch (_) {
    return null;
  }
}
