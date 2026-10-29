import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../config/context_config.dart';
import 'ollama_service.dart';

class ModelContextProfile {
  final int nativeTokens;
  final int tokens;
  final bool supportsTools;
  final bool metadataKnown;
  final bool supportsVision;
  final bool capabilitiesKnown;

  const ModelContextProfile({
    required this.nativeTokens,
    required this.tokens,
    required this.supportsTools,
    required this.metadataKnown,
    this.supportsVision = false,
    this.capabilitiesKnown = false,
  });
}

class ContextProfileService {
  static final instance = ContextProfileService();
  final Map<String, Map<String, dynamic>> _metadata = {};

  Future<ModelContextProfile> forModel(String model) async {
    var metadata = _metadata[model];
    if (metadata == null) {
      metadata = await OllamaService.instance.showModel(model);
      if (metadata != null) {
        _metadata[model] = metadata;
      }
    }
    final info = metadata?['model_info'];
    final lengths = info is Map
        ? info.entries
            .where((entry) => entry.key.toString().endsWith('.context_length'))
            .map((entry) => entry.value)
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value > 0)
            .toList()
        : <int>[];
    final native = lengths.isEmpty
        ? ContextConfig.unknownModelTokens
        : lengths.reduce(math.min);
    final maximum = math.min(native, ContextConfig.profiles.last);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(ContextConfig.profilesKey);
    final profiles = stored == null ? <String, dynamic>{} : jsonDecode(stored);
    final preferred = profiles is Map ? profiles[model] : null;
    final requested =
        preferred is int && ContextConfig.profiles.contains(preferred)
            ? preferred
            : ContextConfig.defaultTokens;
    final capabilities = metadata?['capabilities'];
    return ModelContextProfile(
      nativeTokens: native,
      tokens: math.min(requested, maximum),
      supportsTools: capabilities is List && capabilities.contains('tools'),
      metadataKnown: lengths.isNotEmpty,
      supportsVision: capabilities is List && capabilities.contains('vision'),
      capabilitiesKnown: capabilities is List,
    );
  }

  Future<void> setTokens(String model, int tokens) async {
    final profile = await forModel(model);
    if (!ContextConfig.profiles.contains(tokens) ||
        tokens > profile.nativeTokens) {
      throw ArgumentError('Contexto no admitido por el modelo.');
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(ContextConfig.profilesKey);
    final profiles = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    profiles[model] = tokens;
    if (!await prefs.setString(
        ContextConfig.profilesKey, jsonEncode(profiles))) {
      throw StateError('No se pudo guardar el perfil de contexto.');
    }
  }
}
