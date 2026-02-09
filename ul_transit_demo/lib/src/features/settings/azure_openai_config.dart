const defaultBffUrl = String.fromEnvironment('BFF_URL', defaultValue: 'http://localhost:8001/plan');

class AzureOpenAIConfig {
  AzureOpenAIConfig({
    required this.endpoint,
    required this.apiKey,
    required this.deployment,
    required this.apiVersion,
    required this.useProxy,
    required this.proxyUrl,
  });

  final String endpoint;
  final String apiKey;
  final String deployment;
  final String apiVersion;
  final bool useProxy;
  final String proxyUrl;

  bool get proxyEnabled => useProxy && proxyUrl.isNotEmpty;
  bool get isComplete {
    if (proxyEnabled) return true;
    return endpoint.isNotEmpty && apiKey.isNotEmpty && deployment.isNotEmpty && apiVersion.isNotEmpty;
  }

  factory AzureOpenAIConfig.bff({String proxyUrl = defaultBffUrl}) => AzureOpenAIConfig(
        endpoint: '',
        apiKey: '',
        deployment: '',
        apiVersion: '',
        useProxy: true,
        proxyUrl: proxyUrl,
      );

  AzureOpenAIConfig copyWith({
    String? endpoint,
    String? apiKey,
    String? deployment,
    String? apiVersion,
    bool? useProxy,
    String? proxyUrl,
  }) {
    return AzureOpenAIConfig(
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      deployment: deployment ?? this.deployment,
      apiVersion: apiVersion ?? this.apiVersion,
      useProxy: useProxy ?? this.useProxy,
      proxyUrl: proxyUrl ?? this.proxyUrl,
    );
  }

  factory AzureOpenAIConfig.empty() => AzureOpenAIConfig(endpoint: '', apiKey: '', deployment: '', apiVersion: '', useProxy: false, proxyUrl: '');

  Map<String, String> toJson() => {
        'endpoint': endpoint,
        'apiKey': apiKey,
        'deployment': deployment,
        'apiVersion': apiVersion,
        'useProxy': useProxy.toString(),
        'proxyUrl': proxyUrl,
      };

  factory AzureOpenAIConfig.fromJson(Map<String, dynamic> json) {
    return AzureOpenAIConfig(
      endpoint: (json['endpoint'] ?? '') as String,
      apiKey: (json['apiKey'] ?? '') as String,
      deployment: (json['deployment'] ?? '') as String,
      apiVersion: (json['apiVersion'] ?? '') as String,
      useProxy: (json['useProxy'] ?? 'false').toString() == 'true',
      proxyUrl: (json['proxyUrl'] ?? '') as String,
    );
  }
}
