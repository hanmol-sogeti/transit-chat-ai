import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'azure_openai_config.dart';
import 'settings_repository.dart';
import '../env/env_provider.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.read(secureStorageProvider)));

final azureConfigProvider = StateNotifierProvider<AzureConfigNotifier, AsyncValue<AzureOpenAIConfig>>((ref) {
  final envMap = ref.watch(envFileProvider).maybeWhen(data: (m) => m, orElse: () => <String, String>{});
  final notifier = AzureConfigNotifier(ref.read(settingsRepositoryProvider));
  // Load stored config and prefer values from env file when available.
  notifier.loadWithEnv(envMap);
  return notifier;
});

class AzureConfigNotifier extends StateNotifier<AsyncValue<AzureOpenAIConfig>> {
  AzureConfigNotifier(this._repository) : super(const AsyncLoading());

  final SettingsRepository _repository;

  Future<void> load() async {
    // Delegate to loadWithEnv with empty env map so logic is centralized.
    await loadWithEnv(<String, String>{});
    return;
  }

  /// Same as [load] but prefer values from an env file map when provided.
  Future<void> loadWithEnv(Map<String, String> env) async {
    // Try secure storage first
    final loaded = await AsyncValue.guard(() => _repository.loadAzureConfig());
    AzureOpenAIConfig base = (loaded.hasValue && loaded.value != null) ? loaded.value! : AzureOpenAIConfig.empty();

    if (base.endpoint.isEmpty && base.apiKey.isEmpty) {
      final envEndpoint = env['AZURE_OPENAI_ENDPOINT'] ?? Platform.environment['AZURE_OPENAI_ENDPOINT'] ?? '';
      final envKey = env['AZURE_OPENAI_API_KEY'] ?? Platform.environment['AZURE_OPENAI_API_KEY'] ?? '';
      final envDeployment = env['AZURE_OPENAI_DEPLOYMENT'] ?? Platform.environment['AZURE_OPENAI_DEPLOYMENT'] ?? '';
      final envApiVersion = env['AZURE_OPENAI_API_VERSION'] ?? Platform.environment['AZURE_OPENAI_API_VERSION'] ?? '';
      final useProxy = (env['AZURE_USE_PROXY'] ?? Platform.environment['AZURE_USE_PROXY'] ?? 'false').toLowerCase() == 'true';
      final proxyUrl = env['AZURE_OPENAI_PROXY'] ?? Platform.environment['AZURE_OPENAI_PROXY'] ?? '';

      base = AzureOpenAIConfig(
        endpoint: envEndpoint,
        apiKey: envKey,
        deployment: envDeployment,
        apiVersion: envApiVersion,
        useProxy: useProxy,
        proxyUrl: proxyUrl,
      );
    }

    // If a Trafiklab key is present and a proxy was stored (likely from older setups),
    // clear the proxy so the app will call Trafiklab/OpenAI directly.
    final trafikKey = env['TRAFIKLAB_KEY'] ?? Platform.environment['TRAFIKLAB_KEY'] ?? '';
    if (trafikKey.isNotEmpty && base.useProxy && (base.proxyUrl.contains('localhost') || base.proxyUrl.isEmpty)) {
      final cleared = base.copyWith(useProxy: false, proxyUrl: '');
      try {
        await _repository.saveAzureConfig(cleared);
      } catch (_) {}
      base = cleared;
    }

    state = AsyncValue.data(base);
  }

  Future<void> save(AzureOpenAIConfig config) async {
    state = const AsyncLoading();
    try {
      await _repository.saveAzureConfig(config);
      state = AsyncValue.data(config);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
