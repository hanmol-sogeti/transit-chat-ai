import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ul_transit_demo/src/features/chat/azure_chat_client.dart';
import 'package:ul_transit_demo/src/features/settings/azure_openai_config.dart';

void main() {
  // Uses the local BFF by default; override with env BFF_URL if needed.
  final bffUrl = Platform.environment['BFF_URL'] ?? defaultBffUrl;
  final client = AzureChatClient(http.Client());
  final config = AzureOpenAIConfig.bff(proxyUrl: bffUrl);

  setUpAll(() async {
    // Quick health check; if unreachable, skip the suite.
    final uri = Uri.parse(bffUrl);
    final health = uri.replace(path: '/health', query: '');
    try {
      final resp = await http.get(health).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        throw Exception('Health returned ${resp.statusCode}');
      }
    } catch (e) {
      // Mark the suite as skipped if the backend is not up.
      throw TestFailure('Skipping: BFF not reachable at $health ($e)');
    }
  });

  group('Chat integration via BFF', () {
    test('testConnection returns a response', () async {
      final result = await client.testConnection(config);
      expect(result, isNotEmpty);
    });

    test('planTrip returns a plan', () async {
      final result = await client.planTrip(
        prompt: 'Plan a trip from Main Station to Central Park at 5pm with few transfers',
        config: config,
      );
      expect(result.trim(), isNotEmpty);
    });
  });
}