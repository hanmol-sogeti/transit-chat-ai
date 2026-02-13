import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
// Avoid importing flutter_dotenv in native build paths; prefer Platform.environment at runtime.

import '../env/env_provider.dart';
import 'trafiklab_api.dart';
import 'trafiklab_repository.dart';

final trafiklabApiProvider = Provider<TrafikLabApi>((ref) {
  // Prefer a local .env file (envFileProvider) -> Platform.environment.
  final env = ref.watch(envFileProvider).maybeWhen(data: (m) => m, orElse: () => <String, String>{});
  final key = env['TRAFIKLAB_KEY'] ?? Platform.environment['TRAFIKLAB_KEY'] ?? '';
  final base = env['TRAFIKLAB_BASE_URL'] ?? Platform.environment['TRAFIKLAB_BASE_URL'] ?? 'https://api.trafiklab.se';
  return TrafikLabApi(http.Client(), key, baseUrl: base);
});

final trafiklabRepositoryProvider = Provider<TrafikLabRepository>((ref) {
  final api = ref.watch(trafiklabApiProvider);
  return TrafikLabRepository(api);
});
