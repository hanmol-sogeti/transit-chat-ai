import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../settings/azure_openai_config.dart';
import '../settings/settings_controller.dart';
import 'azure_chat_client.dart';

class ChatMessage {
  ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

final azureChatClientProvider = Provider((ref) => AzureChatClient(http.Client()));

final chatSessionProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  final configValue = ref.watch(azureConfigProvider);
  final client = ref.watch(azureChatClientProvider);
  return ChatNotifier(configValue, client);
});

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier(this._configValue, this._client) : super(const []);

  final AsyncValue<AzureOpenAIConfig> _configValue;
  final AzureChatClient _client;

  bool get _ready => _configValue.hasValue && _configValue.value!.isComplete;

  Future<void> send(String prompt) async {
    state = [...state, ChatMessage(text: prompt, isUser: true)];
    if (!_ready) {
      state = [...state, ChatMessage(text: 'Add Azure OpenAI settings first (or enable proxy in Settings).', isUser: false)];
      return;
    }
    final config = _configValue.value!;
    try {
      final reply = await _client.planTrip(prompt: prompt, config: config);
      state = [...state, ChatMessage(text: reply, isUser: false)];
    } catch (e) {
      debugPrint('[chat] send error: $e');
      state = [...state, ChatMessage(text: 'Chat failed: $e', isUser: false)];
    }
  }
}
