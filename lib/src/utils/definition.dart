import 'dart:io' show Platform;

import 'package:equatable/equatable.dart';

/// Key used to define script description.
const String descriptionDefinitionKey = '(description)';

/// Key used to define scripts.
const String scriptsDefinitionKey = '(scripts)';

/// Key used to select how a list of scripts is executed.
const String executionDefinitionKey = '(execution)';

/// Key used to define a default script for a nested command group.
const String defaultDefinitionKey = '(default)';

/// Key used to set the working directory for a script.
const String workdirDefinitionKey = '(workdir)';

/// Key used to define aliases for a script.
const String aliasesDefinitionKey = '(aliases)';

/// Key used to define reusable variables for script interpolation.
const String variablesDefinitionKey = '(variables)';

/// Platform-specific script keys.
const String linuxDefinitionKey = '(linux)';
const String macosDefinitionKey = '(macos)';
const String windowsDefinitionKey = '(windows)';

/// Returns the metadata key for the current OS, or `null` on unsupported platforms.
String? get currentPlatformKey {
  if (Platform.isLinux) return linuxDefinitionKey;
  if (Platform.isMacOS) return macosDefinitionKey;
  if (Platform.isWindows) return windowsDefinitionKey;
  return null;
}

/// Whether [input] is a shape that can be parsed as a list of commands.
bool _isScriptValue(dynamic input) => input is String || input is List;

/// Returns the value that makes [map] directly runnable on the current
/// platform, or `null` if it only holds nested command groups and metadata.
///
/// The current platform key takes precedence over [scriptsDefinitionKey],
/// which in turn takes precedence over [defaultDefinitionKey].
dynamic runnableScripts(Map<dynamic, dynamic> map) {
  final platformKey = currentPlatformKey;
  if (platformKey != null && _isScriptValue(map[platformKey])) return map[platformKey];
  if (_isScriptValue(map[scriptsDefinitionKey])) return map[scriptsDefinitionKey];
  if (_isScriptValue(map[defaultDefinitionKey])) return map[defaultDefinitionKey];
  return null;
}

/// Parses a list from yaml input.
///
/// Can accept a `List` or a `String`.
List<String> _toStringList(dynamic input) {
  if (input is List) return input.map((e) => e.toString()).toList();
  if (input is String) return [input];
  throw ArgumentError.value(input, '(scripts)', 'must be a String or List');
}

/// A typical script definition.
///
/// [description] - is a short descriptive message about
/// the script which will be shown when you use `merry ls -d`.
///
/// [scripts] - is a list of commands/scripts to execute.
///
/// [execution] - is `once` to stop after the first failed script, or
/// `multiple` to run every script.
///
/// [workdir] - optional working directory to run the scripts in.
class Definition extends Equatable {
  @override
  List<Object?> get props => [description, scripts, execution, workdir];

  /// Description message.
  final String? description;

  /// Scripts contained in the definition.
  final List<String> scripts;

  /// Execution mode for the scripts.
  final String execution;

  /// Optional working directory for script execution.
  final String? workdir;

  /// Constructs a constant [Definition] instance.
  const Definition({
    this.description,
    required this.scripts,
    this.execution = 'multiple',
    this.workdir,
  });

  /// Creates a [Definition] instance from a [dynamic] input.
  /// The input can be a [Map], [List] or [String].
  factory Definition.from(dynamic input) {
    if (input is Map) {
      final description = input[descriptionDefinitionKey] as String?;
      final scripts = input[scriptsDefinitionKey] as dynamic;
      final execution = input[executionDefinitionKey] as String? ?? 'multiple';
      // Reject typos like `onc` or `once ` instead of silently falling back to
      // `multiple`, which would run every command after a failure.
      if (execution != 'once' && execution != 'multiple') {
        throw FormatException(
          'Invalid `(execution)` value "$execution"; expected "once" or "multiple".',
        );
      }
      final workdir = input[workdirDefinitionKey] as String?;

      return Definition(
        description: description,
        scripts: _toStringList(scripts),
        execution: execution,
        workdir: workdir,
      );
    } else {
      return Definition(scripts: _toStringList(input));
    }
  }
}
