import 'package:merry/src/utils/definition.dart' show runnableScripts;

/// Json serializable map.
typedef JsonMap = Map<String, dynamic>;

final _metaKeyPattern = RegExp(r'^\(\w+\)$');

extension ToJsonMapExtension on Map<dynamic, dynamic> {
  /// Takes a `Map` and returns a `JsonMap`
  JsonMap toJsonMap() {
    final self = this;
    return self.map(
      (key, value) => MapEntry(key.toString(), value is Map ? value.toJsonMap() : value),
    );
  }

  JsonMap asJsonMap() => this is JsonMap ? this as JsonMap : toJsonMap();
}

extension JsonMapExtension on JsonMap {
  /// Gets valid paths to access values from a map of script definitions.
  List<String> getPaths() {
    final self = this;
    final result = <String>[];
    for (final k in self.keys) {
      if (_metaKeyPattern.hasMatch(k)) continue;
      final value = self[k];
      if (value is Map) {
        final map = value.asJsonMap();
        // a group can be runnable itself and still hold sub-commands
        if (runnableScripts(map) != null) result.add(k);
        result.addAll(map.getPaths().map((v) => '$k $v'));
      } else {
        result.add(k);
      }
    }
    return result.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList()..sort();
  }

  /// Searches for a given path in the map.
  dynamic lookup(String path) {
    JsonMap data = this;
    final keys = path.trim().split(' ');
    for (final entry in keys.asMap().entries) {
      final isLastKey = entry.key == keys.length - 1;
      final key = entry.value;
      final value = data[key];
      if (!isLastKey && value is Map) {
        data = value.asJsonMap();
        continue;
      }
      return value;
    }
  }
}
