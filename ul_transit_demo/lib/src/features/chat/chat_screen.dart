import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_shell.dart';
import '../map/map_route_provider.dart';
import '../settings/settings_controller.dart';
import 'chat_notifier.dart';

class TripChatScreen extends ConsumerStatefulWidget {
  const TripChatScreen({super.key});

  @override
  ConsumerState<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends ConsumerState<TripChatScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatSessionProvider);
    final config = ref.watch(azureConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat Trip Planner')),
      body: Column(
        children: [
          if (config.hasValue && !config.value!.isComplete)
            const _ConfigBanner(text: 'Add Azure OpenAI settings to enable live chat.'),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final looksLikeTrip = !msg.isUser && _looksLikeTrip(msg.text);

                return Column(
                  crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: msg.isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg.text),
                      ),
                    ),
                    if (looksLikeTrip)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('Visa på karta'),
                              onPressed: () {
                                ref.read(mapRouteRequestProvider.notifier).state = MapRouteRequest.fromText(msg.text);
                                ref.read(navIndexProvider.notifier).state = 1; // Map tab
                              },
                            ),
                            ActionChip(
                              label: const Text('Boka'),
                              onPressed: () => ref.read(navIndexProvider.notifier).state = 3, // Tickets tab
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'Where do you want to go?'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(chatSessionProvider.notifier).send(text);
    _controller.clear();
  }
}

bool _looksLikeTrip(String text) {
  final lower = text.toLowerCase();
  return lower.contains('resa') || lower.contains('boka') || lower.contains('till') || lower.contains('avgång');
}

class _ConfigBanner extends StatelessWidget {
  const _ConfigBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
