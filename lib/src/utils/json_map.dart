import 'dart:collection' show HashSet;

import 'package:merry/src/utils/definition.dart' show runnableScripts;

/// Json serializable map.
typedef JsonMap = Map<String, dynamic>;

final _metaKeyPattern = RegExp(r'^\(\w+\)$');

/// The most entries one conversion may visit: every map and list, and every
/// map entry and list element inside them, counting each occurrence of a
/// repeated alias.
///
/// A real config holds a few hundred entries at most, so this leaves orders of
/// magnitude of room, while a file that repeats an alias (to a large
/// collection, or in a fan-out where each level aliases the one before several
/// times) stops here instead of making the work grow with every repetition.
const _maxEntries = 100000;

/// The deepest map and list nesting one conversion may follow.
///
/// Script groups nest a handful of levels at most; the limit only bounds the
/// recursion so a deeply nested file fails with a clear error.
const _maxDepth = 64;

extension ToJsonMapExtension on Map<dynamic, dynamic> {
  /// Takes a `Map` and returns a `JsonMap`
  JsonMap toJsonMap() {
    return _toJsonMap(this, HashSet<Map<dynamic, dynamic>>.identity(), _EntryBudget());
  }

  JsonMap asJsonMap() => this is JsonMap ? this as JsonMap : toJsonMap();
}

/// Counts the entries visited across one whole conversion.
class _EntryBudget {
  int used = 0;
}

JsonMap _toJsonMap(
  Map<dynamic, dynamic> map,
  Set<Map<dynamic, dynamic>> ancestors,
  _EntryBudget budget,
) {
  if (!ancestors.add(map)) {
    throw const FormatException('Cyclic map aliases are not supported.');
  }
  // `ancestors` holds exactly the maps on the current path, so its size is the
  // nesting depth of `map`
  _checkDepth(ancestors.length);
  _countEntry(budget);

  final result = <String, dynamic>{};
  // Iterate keys and reject collection-valued keys (e.g. a YAML `? *anchor`
  // that aliases the mapping itself) before any `map[key]` lookup: hashing a
  // cyclic collection key deep-recurses inside package:yaml and overflows the
  // stack before the identity cycle check above could ever run.
  for (final key in map.keys) {
    if (key is Map || key is List) {
      throw const FormatException('Collection map keys are not supported.');
    }
    _countEntry(budget);
    final value = map[key];
    if (value is Map) {
      result[key.toString()] = _toJsonMap(value, ancestors, budget);
    } else {
      // lists pass through unchanged, but an alias fan-out of lists expands
      // later just the same, so they count against the same limits
      if (value is List) _checkCollection(value, ancestors.length + 1, budget);
      result[key.toString()] = value;
    }
  }
  ancestors.remove(map);
  return result;
}

void _countEntry(_EntryBudget budget) {
  if (++budget.used > _maxEntries) {
    throw const FormatException(
      'The config expands to too many entries (more than $_maxEntries after resolving aliases).',
    );
  }
}

void _checkDepth(int depth) {
  if (depth > _maxDepth) {
    throw const FormatException(
      'The config nests too deeply (more than $_maxDepth levels).',
    );
  }
}

/// Counts a collection that is passed through unconverted, and every entry
/// inside it, against the entry and depth limits.
///
/// The depth limit also stops a cycle here, since this walk keeps no ancestors.
void _checkCollection(Object collection, int depth, _EntryBudget budget) {
  _checkDepth(depth);
  _countEntry(budget);
  final children = collection is Map ? collection.values : collection as List;
  for (final child in children) {
    _countEntry(budget);
    if (child is Map || child is List) {
      _checkCollection(child as Object, depth + 1, budget);
    }
  }
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
