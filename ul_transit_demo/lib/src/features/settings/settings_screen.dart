import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'azure_openai_config.dart';
import 'settings_controller.dart';
import '../chat/chat_notifier.dart';
import '../gtfs/gtfs_providers.dart';
import '../booking/booking_models.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _endpoint = TextEditingController();
  final _apiKey = TextEditingController();
  final _deployment = TextEditingController();
  final _apiVersion = TextEditingController(text: '2024-02-15-preview');
  final _proxyUrl = TextEditingController(text: defaultBffUrl);
  bool _useProxy = true; // always on for BFF

  @override
  void dispose() {
    _endpoint.dispose();
    _apiKey.dispose();
    _deployment.dispose();
    _apiVersion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configValue = ref.watch(azureConfigProvider);
    final isWeb = kIsWeb;
    if (configValue.hasValue) {
      final c = configValue.value!;
      if (_endpoint.text.isEmpty && _apiKey.text.isEmpty && _deployment.text.isEmpty) {
        _endpoint.text = c.endpoint;
        _apiKey.text = c.apiKey;
        _deployment.text = c.deployment;
        _apiVersion.text = c.apiVersion;
        _proxyUrl.text = c.proxyUrl.isNotEmpty ? c.proxyUrl : _proxyUrl.text;
        _useProxy = c.useProxy;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Användarprofil', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Namn: ${demoUserProfile.name}'),
                    Text('Kön: ${demoUserProfile.gender}'),
                    Text('Födelsedatum: ${demoUserProfile.birthdate}'),
                    const SizedBox(height: 4),
                    const Text('Hemadress: S:t Göransgatan 33C, Uppsala'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (isWeb) ...[
              Text('Web build uses the backend BFF. No Azure settings needed here. Current BFF: ${_proxyUrl.text}',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            const Text('Azure OpenAI'),
            const SizedBox(height: 8),
            TextField(
              controller: _endpoint,
              decoration: const InputDecoration(labelText: 'Endpoint (https://<resource>.openai.azure.com)'),
              enabled: !isWeb,
            ),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(labelText: 'API key'),
              obscureText: true,
              enabled: !isWeb,
            ),
            TextField(
              controller: _deployment,
              decoration: const InputDecoration(labelText: 'Deployment name'),
              enabled: !isWeb,
            ),
            TextField(
              controller: _apiVersion,
              decoration: const InputDecoration(labelText: 'API version'),
              enabled: !isWeb,
            ),
            SwitchListTile(
              title: const Text('Use BFF (required)'),
              value: _useProxy,
              onChanged: null,
            ),
            TextField(
              controller: _proxyUrl,
              decoration: const InputDecoration(labelText: 'Proxy URL (e.g. http://localhost:8000/chat)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: configValue.isLoading ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save securely'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: configValue.hasValue ? _testConnection : null,
              icon: const Icon(Icons.cloud_done),
              label: const Text('Test connection'),
            ),
            const SizedBox(height: 24),
            const Text('GTFS data'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                await ref.read(gtfsDatabaseProvider).clearAndSeed();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample GTFS reloaded.')));
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reload sample data'),
            ),
            if (configValue.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Error: ${configValue.error}', style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final config = AzureOpenAIConfig(
      endpoint: _endpoint.text.trim(),
      apiKey: _apiKey.text.trim(),
      deployment: _deployment.text.trim(),
      apiVersion: _apiVersion.text.trim(),
      useProxy: _useProxy,
      proxyUrl: _proxyUrl.text.trim(),
    );
    await ref.read(azureConfigProvider.notifier).save(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved locally.')));
    }
  }

  Future<void> _testConnection() async {
    final config = AzureOpenAIConfig(
      endpoint: _endpoint.text.trim(),
      apiKey: _apiKey.text.trim(),
      deployment: _deployment.text.trim(),
      apiVersion: _apiVersion.text.trim(),
      useProxy: _useProxy,
      proxyUrl: _proxyUrl.text.trim(),
    );
    final client = ref.read(azureChatClientProvider);
    try {
      final result = await client.testConnection(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection ok: $result')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test failed: $e')));
      }
    }
  }
}
