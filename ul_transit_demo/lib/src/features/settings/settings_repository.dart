import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'azure_openai_config.dart';

class SettingsRepository {
  SettingsRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _azureKey = 'azure_openai_config_v1';

  Future<AzureOpenAIConfig> loadAzureConfig() async {
    final raw = await _storage.read(key: _azureKey);
    if (raw == null) return AzureOpenAIConfig.empty();
    return AzureOpenAIConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveAzureConfig(AzureOpenAIConfig config) async {
    await _storage.write(key: _azureKey, value: jsonEncode(config.toJson()));
  }
}
