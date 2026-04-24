import 'dart:io';

import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:merry/utils.dart' show Info, JsonMap, ToJsonMapExtension, readYamlMap;
import 'package:path/path.dart' as path;

const String pubspecFileName = 'pubspec.yaml';
const String scriptsKey = 'scripts';

/// A singleton class that reads and caches the content of
/// `pubspec.yaml` in current directory and provides utilities
/// for .
class Pubspec {
  /// File path of `pubspec.yaml` in current directory.
  final String filePath;

  Pubspec({String? currentDirPath})
    : filePath = path.join(currentDirPath ?? Directory.current.path, pubspecFileName);

  /// Text content of `pubspec.yaml` once it has been read,
  /// used as a mean of memoization.
  JsonMap? _content;

  /// Loads the content of `pubspec.yaml` in current directory,
  /// this methods must be called before any other method.
  Future<JsonMap> getContent() async {
    _content ??= await readYamlMap(filePath).then((map) => map.toJsonMap());
    return _content!;
  }

  /// Returns basic information about the package
  /// defined in `pubspec.yaml`.
  Future<Info> getInfo() async {
    final content = await getContent();
    return Info(
      name: content['name'] as String?,
      version: content['version'] as String?,
    );
  }

  /// The file path where the scripts are defined,
  /// used as a mean of memoization.
  String? _source;

  /// Returns the file path where the scripts are defined
  /// which can be either `pubspec.yaml` or a file path
  /// defined in `pubspec.yaml`.
  Future<String> getSource() async {
    _source ??= await _getSourceUncached();
    return _source!;
  }

  Future<String> _getSourceUncached() async {
    final content = await getContent();
    final scripts = content[scriptsKey];

    if (scripts == null) {
      throw MerryError(type: ErrorCode.missingScripts);
    }

    if (scripts is Map) {
      return pubspecFileName;
    } else if (scripts is String) {
      return scripts;
    } else {
      throw MerryError(type: ErrorCode.invalidScripts);
    }
  }

  /// A map of scripts defined in `pubspec.yaml`,
  /// used as a mean of memoization.
  JsonMap? _scripts;

  /// Returns a map of scripts defined in `pubspec.yaml`
  /// or the scripts from the file path defined in `pubspec.yaml`.
  Future<JsonMap> getScripts() async {
    _scripts ??= await _getScriptsUncached();
    return _scripts!;
  }

  Future<JsonMap> _getScriptsUncached() async {
    final source = await getSource();

    if (source == pubspecFileName) {
      final content = await getContent();
      return content[scriptsKey] as JsonMap;
    }

    return readYamlMap(source).then((map) => map.toJsonMap());
  }
}
