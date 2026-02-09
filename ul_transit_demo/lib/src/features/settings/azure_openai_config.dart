class AzureOpenAIConfig {
  AzureOpenAIConfig({
    required this.endpoint,
    required this.apiKey,
    required this.deployment,
    required this.apiVersion,
  });

  final String endpoint;
  final String apiKey;
  final String deployment;
  final String apiVersion;

  bool get isComplete => endpoint.isNotEmpty && apiKey.isNotEmpty && deployment.isNotEmpty && apiVersion.isNotEmpty;

  AzureOpenAIConfig copyWith({
    String? endpoint,
    String? apiKey,
    String? deployment,
    String? apiVersion,
  }) {
    return AzureOpenAIConfig(
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      deployment: deployment ?? this.deployment,
      apiVersion: apiVersion ?? this.apiVersion,
    );
  }

  factory AzureOpenAIConfig.empty() => AzureOpenAIConfig(endpoint: '', apiKey: '', deployment: '', apiVersion: '');

  Map<String, String> toJson() => {
        'endpoint': endpoint,
        'apiKey': apiKey,
        'deployment': deployment,
        'apiVersion': apiVersion,
      };

  factory AzureOpenAIConfig.fromJson(Map<String, dynamic> json) {
    return AzureOpenAIConfig(
      endpoint: (json['endpoint'] ?? '') as String,
      apiKey: (json['apiKey'] ?? '') as String,
      deployment: (json['deployment'] ?? '') as String,
      apiVersion: (json['apiVersion'] ?? '') as String,
    );
  }
}
