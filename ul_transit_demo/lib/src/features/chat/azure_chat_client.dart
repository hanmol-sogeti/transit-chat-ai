import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../settings/azure_openai_config.dart';

class AzureChatClient {
  AzureChatClient(this._http);

  final http.Client _http;

  Future<String> testConnection(AzureOpenAIConfig config) async {
    final uri = Uri.parse(config.proxyUrl);
    final headers = <String, String>{'Content-Type': 'application/json'};

    final body = {
      'prompt': 'ping',
      'temperature': 0.0,
      'max_tokens': 5,
    };

    debugPrint('[chat] testConnection POST ${uri.toString()}');
    final response = await _http.post(uri, headers: headers, body: jsonEncode(body));
    debugPrint('[chat] status ${response.statusCode}: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Prefer BFF schema {"content": "..."}; fall back to OpenAI shape if present.
      final directContent = (json['content'] ?? '').toString();
      final choiceContent = ((json['choices'] as List?)?.first?['message']?['content'] ?? '').toString();
      final content = directContent.isNotEmpty ? directContent : choiceContent;
      return content.isEmpty ? 'ok' : content;
    }
    throw Exception('Azure OpenAI error ${response.statusCode}: ${response.body}');
  }

  Future<String> planTrip({required String prompt, required AzureOpenAIConfig config}) async {
    final uri = Uri.parse(config.proxyUrl);
    final headers = <String, String>{'Content-Type': 'application/json'};

    final body = {
      'prompt': prompt,
      'temperature': 0.3,
      'max_tokens': 180,
    };

    debugPrint('[chat] planTrip POST ${uri.toString()}');
    final response = await _http.post(uri, headers: headers, body: jsonEncode(body));
    debugPrint('[chat] status ${response.statusCode}: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Prefer BFF schema; fall back to OpenAI choices shape if proxy is bypassed.
      final directContent = (json['content'] ?? '').toString();
      final choiceContent = ((json['choices'] as List?)?.first?['message']?['content'] ?? '').toString();
      return directContent.isNotEmpty ? directContent : choiceContent;
    }
    throw Exception('Azure OpenAI error ${response.statusCode}: ${response.body}');
  }
}
