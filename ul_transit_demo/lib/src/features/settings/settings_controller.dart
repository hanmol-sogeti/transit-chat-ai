import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'azure_openai_config.dart';
import 'settings_repository.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.read(secureStorageProvider)));

final azureConfigProvider = StateNotifierProvider<AzureConfigNotifier, AsyncValue<AzureOpenAIConfig>>((ref) {
  return AzureConfigNotifier(ref.read(settingsRepositoryProvider))..load();
});

class AzureConfigNotifier extends StateNotifier<AsyncValue<AzureOpenAIConfig>> {
  AzureConfigNotifier(this._repository) : super(const AsyncLoading());

  final SettingsRepository _repository;

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.loadAzureConfig());
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
