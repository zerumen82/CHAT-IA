import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Entrada de un proveedor configurado por el usuario.
///
/// Contiene la clave y el modelo elegidos. Se serializa a SharedPreferences;
/// nunca se escribe en el código fuente ni en git.
@immutable
class ApiKeyEntry {
  const ApiKeyEntry({
    required this.providerId,
    required this.apiKey,
    this.model = '',
  });

  final String providerId;

  /// Clave en claro dentro del perfil local de la app (decisión del usuario:
  /// SharedPreferences sin dependencias nuevas).
  final String apiKey;

  /// Modelo elegido para este proveedor. Vacío = aún sin elegir.
  final String model;

  ApiKeyEntry copyWith({String? apiKey, String? model}) => ApiKeyEntry(
        providerId: providerId,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'apiKey': apiKey,
        'model': model,
      };

  factory ApiKeyEntry.fromJson(Map<String, dynamic> json) => ApiKeyEntry(
        providerId: json['providerId'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
      );
}

/// Resultado de importar un archivo de claves (p. ej. `APIS.txt`).
@immutable
class ApiImportResult {
  const ApiImportResult({
    this.imported = const <String>[],
    this.updated = const <String>[],
    this.ignored = const <String>[],
    this.unrecognized = const <String>[],
    this.extraKeys = const <String, String>{},
    this.totalParsed = 0,
  });

  /// Proveedores nuevos dados de alta.
  final List<String> imported;

  /// Proveedores que ya existían y cuya clave fue sustituida.
  final List<String> updated;

  /// Líneas del archivo que no aportaron clave (vacías o de solo nombre).
  final List<String> ignored;

  /// Nombres que no pertenecen al catálogo (no se guardan).
  final List<String> unrecognized;

  /// Proveedores a los que el archivo traía **más de una clave** en líneas
  /// sucesivas: se guarda la primera y aquí se documenta la extra para que el
  /// usuario la revise a mano. Nunca se descarta en silencio.
  final Map<String, String> extraKeys;

  /// Líneas con par `nombre: clave` reconocidas en total.
  final int totalParsed;

  bool get hasChanges => imported.isNotEmpty || updated.isNotEmpty;
}

/// Persistencia de las claves/URLs de proveedores cloud.
///
/// Patrón `instance` + `ChangeNotifier`, igual que el resto de servicios.
class ApiKeyStore extends ChangeNotifier {
  ApiKeyStore._();

  static final ApiKeyStore instance = ApiKeyStore._();

  final Map<String, ApiKeyEntry> _entries = <String, ApiKeyEntry>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Proveedores con clave y modelo definidos (los que aparecen en el chat).
  List<ApiKeyEntry> get configured =>
      _entries.values.where((e) => e.apiKey.isNotEmpty).toList(growable: false);

  /// Todas las entradas (incluidas las que aún no tienen modelo elegido).
  List<ApiKeyEntry> get entries =>
      _entries.values.toList(growable: false)..sort(
          (a, b) => a.providerId.compareTo(b.providerId));

  ApiKeyEntry? entry(String providerId) => _entries[providerId];

  String? apiKeyOf(String providerId) => _entries[providerId]?.apiKey;

  String? modelOf(String providerId) {
    final model = _entries[providerId]?.model;
    return (model == null || model.isEmpty) ? null : model;
  }

  /// Modelo cloud seleccionable (`api:<proveedor>/<modelo>`), si está completo.
  List<String> selectableModelIds() => _entries.values
      .where((e) => e.apiKey.isNotEmpty && e.model.isNotEmpty)
      .map((e) => ApiConfig.apiModelId(e.providerId, e.model))
      .toList(growable: false);

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(ApiConfig.storeKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final item in decoded.values) {
            if (item is Map<String, dynamic>) {
              final entry = ApiKeyEntry.fromJson(item);
              if (entry.providerId.isNotEmpty) {
                // Si el modelo está vacío, lo rellenamos con el sugerido
                final existing = _entries[entry.providerId];
                final suggested = ApiConfig.suggestedModelFor(entry.providerId);
                if (entry.model.isEmpty) {
                  _entries[entry.providerId] = ApiKeyEntry(
                    providerId: entry.providerId,
                    apiKey: entry.apiKey,
                    model: suggested.isNotEmpty ? suggested : existing?.model ?? '',
                  );
                } else {
                  _entries[entry.providerId] = entry;
                }
              }
            }
          }
        }
      } on FormatException {
        // Preferencias corruptas: se empieza vacío, nunca un fallo destructivo.
        _entries.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Guarda (o sustituye) la entrada de un proveedor.
  ///
  /// Lanza [ArgumentError] si el proveedor no está en el catálogo o si no se
  /// indica nada que guardar.
  Future<void> save({
    required String providerId,
    required String apiKey,
    String model = '',
    bool replaceExisting = true,
  }) async {
    if (ApiConfig.byId(providerId) == null) {
      throw ArgumentError('Proveedor no incluido en el catálogo: $providerId');
    }
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim();
    if (trimmedKey.isEmpty && trimmedModel.isEmpty) {
      throw ArgumentError('No hay nada que guardar.');
    }
    final existing = _entries[providerId];
    if (existing != null && !replaceExisting) {
      return;
    }
    _entries[providerId] = ApiKeyEntry(
      providerId: providerId,
      apiKey: trimmedKey,
      model: trimmedModel.isNotEmpty
          ? trimmedModel
          : existing?.model.trim() ?? '',
    );
    await _persist();
    notifyListeners();
  }

  /// Solo cambia el modelo de un proveedor ya dado de alta.
  Future<void> setModel(String providerId, String model) async {
    final existing = _entries[providerId];
    if (existing == null) {
      throw ArgumentError('El proveedor todavía no tiene clave guardada.');
    }
    _entries[providerId] = existing.copyWith(model: model.trim());
    await _persist();
    notifyListeners();
  }

  /// Elimina la entrada completa de un proveedor.
  Future<void> remove(String providerId) async {
    if (_entries.remove(providerId) != null) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      for (final entry in _entries.values) entry.providerId: entry.toJson(),
    };
    if (!await prefs.setString(ApiConfig.storeKey, jsonEncode(payload))) {
      throw StateError('No se pudieron guardar las claves de API.');
    }
  }

  /// Limpia todo (solo para pruebas y para el usuario desde la UI).
  Future<void> clear() async {
    _entries.clear();
    await _persist();
    notifyListeners();
  }

  // ─────────────────────────── Importación de APIS.txt ──────────────────────

  /// Analiza el contenido de un archivo de claves.
  ///
  /// Tolerante a los formatos observados: `NOMBRE : clave`, `NOMBRE= clave`,
  /// `NOMBRE; clave`, `NOMBRE:clave`, líneas en blanco, sangrías y líneas de
  /// continuación sin separador (p. ej. una segunda clave bajo el mismo
  /// nombre). **Solo analiza**: no escribe nada.
  @visibleForTesting
  ApiImportResult parse(String content) => _analyze(content).result;

  /// Analiza y devuelve además las entradas resultantes (sin guardar).
  ({ApiImportResult result, Map<String, ApiKeyEntry> entries}) _analyze(
      String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final pairs = <(int, String, String)>[]; // (linea, nombre, clave)
    final bare = <(int, String)>[]; // (linea, clave sin nombre)

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final match = RegExp(r'^([^:=;]+)\s*[:=;]\s*(.+)$').firstMatch(trimmed);
      if (match != null) {
        final name = match.group(1)!.trim();
        final value = match.group(2)!.trim();
        if (value.isEmpty) {
          continue;
        }
        pairs.add((i, name, value));
      } else {
        bare.add((i, trimmed));
      }
    }

    final result = <String, ApiKeyEntry>{};
    final imported = <String>[];
    final updated = <String>[];
    final ignored = <String>[];
    final unrecognized = <String>[];
    final extraKeys = <String, String>{};
    var order = 0;

    for (final (lineIndex, name, value) in pairs) {
      final providerId = ApiConfig.resolveAlias(name);
      if (providerId == null) {
        unrecognized.add('línea ${lineIndex + 1}: $name');
        continue;
      }
      final already = result[providerId];
      if (already == null) {
        result[providerId] = ApiKeyEntry(
          providerId: providerId,
          apiKey: value,
        );
        order++;
      } else {
        // Segunda clave para el mismo proveedor en el mismo archivo: se
        // conserva la primera y la extra se reporta, nunca se descarta.
        extraKeys[providerId] = value;
      }
    }

    // Líneas sin separador: si siguen a un proveedor conocido, son claves
    // extra; si no, se ignoran dejando constancia.
    for (final (lineIndex, value) in bare) {
      final previousLine =
          lineIndex > 0 ? lines[lineIndex - 1].trim() : '';
      final previousName = RegExp(r'^([^:=;]+)\s*[:=;]')
          .firstMatch(previousLine)
          ?.group(1);
      final providerId =
          previousName == null ? null : ApiConfig.resolveAlias(previousName);
      if (providerId != null && result.containsKey(providerId)) {
        extraKeys[providerId] = value;
      } else {
        ignored.add('línea ${lineIndex + 1}: $value');
      }
    }

    final sortedIds = result.keys.toList()..sort();
    for (final providerId in sortedIds) {
      if (_entries.containsKey(providerId)) {
        updated.add(providerId);
      } else {
        imported.add(providerId);
      }
    }

    return (
      result: ApiImportResult(
        imported: imported,
        updated: updated,
        ignored: ignored,
        unrecognized: unrecognized,
        extraKeys: extraKeys,
        totalParsed: order,
      ),
      entries: result,
    );
  }

  /// Importa `content` y guarda los proveedores reconocidos.
  ///
  /// Si un proveedor ya existía, su clave se **sustituye** (el usuario acaba
  /// de elegir importar a propósito). Devuelve el resultado del análisis.
  Future<ApiImportResult> import(String content) async {
    final analysis = _analyze(content);
    final parsed = analysis.result;
    for (final entry in analysis.entries.values) {
      final existing = _entries[entry.providerId];
      final suggested = ApiConfig.suggestedModelFor(entry.providerId);
      final proposed = entry.model.trim();
      // Si ya tenía modelo, no se cambia; si está vacío, se rellena con el sugerido.
      _entries[entry.providerId] = ApiKeyEntry(
        providerId: entry.providerId,
        apiKey: entry.apiKey,
        model: proposed.isNotEmpty && existing?.model == null
            ? proposed
            : (existing?.model.trim().isNotEmpty == true ? existing!.model.trim() : (suggested.isNotEmpty ? suggested : '')),
      );
    }
    if (analysis.entries.isNotEmpty) {
      await _persist();
      notifyListeners();
    }
    return parsed;
  }

  /// Solo para pruebas: recarga el estado desde cero.
  @visibleForTesting
  void resetForTest() {
    _entries.clear();
    _loaded = false;
  }
}
