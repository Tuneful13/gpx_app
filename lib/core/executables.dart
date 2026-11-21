import 'dart:io';

/// Busca en el PATH el primer ejecutable disponible de [names] (en ese orden).
/// Devuelve su ruta completa, o null si no hay ninguno.
String? findExecutable(List<String> names, {String? pathEnv}) {
  final path = pathEnv ?? Platform.environment['PATH'] ?? '';
  final dirs = path.split(':').where((d) => d.isNotEmpty);
  for (final name in names) {
    for (final dir in dirs) {
      final file = File('$dir/$name');
      try {
        if (file.existsSync()) return file.path;
      } catch (_) {}
    }
  }
  return null;
}
