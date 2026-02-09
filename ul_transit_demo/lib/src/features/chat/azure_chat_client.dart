import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/azure_openai_config.dart';

class AzureChatClient {
  AzureChatClient(this._http);

  final http.Client _http;

  Uri _buildUri(AzureOpenAIConfig config) {
    return Uri.parse('${config.endpoint}/openai/deployments/${config.deployment}/chat/completions?api-version=${config.apiVersion}');
  }

  Future<String> testConnection(AzureOpenAIConfig config) async {
    final response = await _http.post(
      _buildUri(config),
      headers: {
        'api-key': config.apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'temperature': 0.0,
        'max_tokens': 5,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = ((json['choices'] as List?)?.first?['message']?['content'] ?? '').toString();
      return content.isEmpty ? 'ok' : content;
    }
    throw Exception('Azure OpenAI error ${response.statusCode}: ${response.body}');
  }

  Future<String> planTrip({required String prompt, required AzureOpenAIConfig config}) async {
    final response = await _http.post(
      _buildUri(config),
      headers: {
        'api-key': config.apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content': 'You are a UL transit planner. Extract origin, destination, time, and preferences succinctly. Respond with a short summary.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.3,
        'max_tokens': 180,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = ((json['choices'] as List?)?.first?['message']?['content'] ?? '').toString();
      return content;
    }
    throw Exception('Azure OpenAI error ${response.statusCode}: ${response.body}');
  }
}
