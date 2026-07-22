/// Mirrors api/api.py's ModelConfig/Provider/Model response shape from
/// GET /models/config -- the same data source UserSelector.tsx uses on the
/// web app to populate its provider/model picker.
class LlmModel {
  final String id;
  final String name;
  const LlmModel({required this.id, required this.name});
  factory LlmModel.fromJson(Map<String, dynamic> json) =>
      LlmModel(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '');
}

class LlmProvider {
  final String id;
  final String name;
  final List<LlmModel> models;
  final bool supportsCustomModel;

  const LlmProvider({
    required this.id,
    required this.name,
    required this.models,
    required this.supportsCustomModel,
  });

  factory LlmProvider.fromJson(Map<String, dynamic> json) => LlmProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        models: (json['models'] as List?)?.map((e) => LlmModel.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        supportsCustomModel: json['supportsCustomModel'] as bool? ?? false,
      );
}

class ModelsConfig {
  final List<LlmProvider> providers;
  final String defaultProvider;

  const ModelsConfig({required this.providers, required this.defaultProvider});

  factory ModelsConfig.fromJson(Map<String, dynamic> json) => ModelsConfig(
        providers: (json['providers'] as List?)?.map((e) => LlmProvider.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        defaultProvider: json['defaultProvider'] as String? ?? '',
      );

  LlmProvider? providerById(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return providers.isNotEmpty ? providers.first : null;
  }
}
