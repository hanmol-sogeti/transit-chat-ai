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
    final loaded = await AsyncValue.guard(() => _repository.loadAzureConfig());
    final base = (loaded.hasValue && loaded.value != null) ? loaded.value! : AzureOpenAIConfig.empty();
    final cfg = base.copyWith(useProxy: true, proxyUrl: defaultBffUrl);
    state = AsyncValue.data(cfg);
  }

  Future<void> save(AzureOpenAIConfig config) async {
    final forced = config.copyWith(useProxy: true, proxyUrl: defaultBffUrl);
    state = const AsyncLoading();
    try {
      await _repository.saveAzureConfig(forced);
      state = AsyncValue.data(forced);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
