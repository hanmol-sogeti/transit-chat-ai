import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../settings/azure_openai_config.dart';
import '../settings/settings_controller.dart';
import 'azure_chat_client.dart';
import '../booking/booking_models.dart';
import '../map/map_route_provider.dart';

class ChatMessage {
  ChatMessage({required this.text, required this.isUser, String? id}) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
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
  ChatNotifier(this._configValue, this._client)
      : super([
          ChatMessage(
            text: 'Hej ${demoUserProfile.name}! Hur kan jag hjälpa dig idag: boka resa, se avgångar eller kolla förseningar?',
            isUser: false,
          ),
        ]);

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
      final reply = await _client.planTrip(prompt: _withUserContext(prompt), config: config);
      // Append the model reply without modification.
      state = [...state, ChatMessage(text: reply, isUser: false)];
    } catch (e) {
      debugPrint('[chat] send error: $e');
      state = [...state, ChatMessage(text: 'Chat failed: $e', isUser: false)];
    }
  }
}

String _withUserContext(String userPrompt) {
  const home = MapRouteRequest.defaultOrigin;
  final profile = demoUserProfile;
  return '''Användarkontext:
- Namn: ${profile.name}
- Kön: ${profile.gender}
- Född: ${profile.birthdate}
- Hemadress (ursprung): $home, Uppsala

Instruktioner till assistenten:
- Planera resa från hemadressen om inget ursprung anges.
- Föreslå nästa avgångar (upp till 3), linje och hållplats.
- Svara kort på svenska, lista hållplats, linje och avgångstid.
- Inkludera destinationen användaren bad om.

Användarfråga:
$userPrompt''';
}
