import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Dónde se guardan los ajustes. Síncrono: la caja de Hive ya está abierta
/// cuando arranca la app, así los ajustes están disponibles desde el primer frame.
abstract class SettingsStore {
  Map<String, Object?> load();
  Future<void> save(Map<String, Object> values);
}

/// Solo en memoria: valor por defecto en tests y respaldo si falla el disco.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Map<String, Object?>? initial])
      : _data = {...?initial};

  Map<String, Object?> _data;

  @override
  Map<String, Object?> load() => {..._data};

  @override
  Future<void> save(Map<String, Object> values) async {
    _data = {...values};
  }
}

class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore(this._box);

  final Box<dynamic> _box;

  @override
  Map<String, Object?> load() {
    return {
      for (final key in _box.keys)
        if (key is String) key: _box.get(key) as Object?,
    };
  }

  @override
  Future<void> save(Map<String, Object> values) async {
    try {
      await _box.putAll(values);
    } catch (e) {
      // Perder un ajuste es mejor que tumbar la app.
      debugPrint('No se pudieron guardar los ajustes: $e');
    }
  }
}
