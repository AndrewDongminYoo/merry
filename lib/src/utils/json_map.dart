/// Json serializable map.
typedef JsonMap = Map<String, dynamic>;

extension ToJsonMapExtension on Map {
  /// Takes a `Map` and returns a `JsonMap`
  JsonMap toJsonMap() {
    final self = this;
    return self.map(
      (key, value) => MapEntry(key.toString(), value is Map ? value.toJsonMap() : value),
    );
  }
}

extension JsonMapExtension on JsonMap {
  /// Gets valid paths to access values from a map of script definitions.
  List<String> getPaths() {
    final self = this;
    final result = <String>[];
    final keys = self.keys.toList()..sort();
    for (final k in keys) {
      final value = self[k];
      if (value is Map) {
        final nestedMap = value is JsonMap ? value : value.toJsonMap();
        result.addAll(nestedMap.getPaths().map((v) => '$k $v'));
      } else if (RegExp(r'\(\w+\)').matchAsPrefix(k) != null) {
        continue;
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
        data = value is JsonMap ? value : value.toJsonMap();
        continue;
      }
      return value;
    }
  }
}
