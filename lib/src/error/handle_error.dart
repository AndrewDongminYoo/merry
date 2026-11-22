import 'dart:io' show stderr;

import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:merry/src/utils/display_safe.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:tint/tint.dart';

/// Handles errors based on [ErrorCode].
void handleError(MerryError e) {
  final buffer = StringBuffer();
  final prefix = 'merry ${"ERR!".red()}';

  buffer.writeln('$prefix Code ${e.type.name.cyan()}');

  switch (e.type) {
    case ErrorCode.scriptNotDefined:
      final scriptRun = e.body['script'] as String;
      final suggestions = e.body['suggestions'] as List<String>;

      buffer.writeln('$prefix Unable to find script named "${displaySafe(scriptRun)}".');

      final bestMatch = StringSimilarity.findBestMatch(
        scriptRun,
        suggestions,
      ).bestMatch;
      if (bestMatch.rating != null && bestMatch.rating! >= 0.5) {
        buffer.writeln();
        buffer.writeln('$prefix Did you mean to run this?');
        buffer.writeln('$prefix    ${displaySafe('${bestMatch.target}')}');
      }

    case ErrorCode.invalidScript:
      final scriptRun = e.body['script'] as String;
      final paths = e.body['paths'] as List<String>? ?? [];
      final nestedScripts = paths.where((path) => path.startsWith('$scriptRun ')).toList();

      if (nestedScripts.isNotEmpty) {
        buffer.writeln('$prefix Script "${displaySafe(scriptRun)}" is a nested script.');

        final bestMatch = StringSimilarity.findBestMatch(
          scriptRun,
          nestedScripts,
        ).bestMatch;
        if (bestMatch.rating != null && bestMatch.rating! >= 0.5) {
          buffer.writeln();
          buffer.writeln('$prefix Did you mean to run this?');
          buffer.writeln('$prefix    ${displaySafe('${bestMatch.target}')}');
        }
      } else {
        buffer.writeln('$prefix Script definition of "${displaySafe(scriptRun)}" is invalid.');
      }

    case ErrorCode.circularReference:
      final cycle = (e.body['cycle'] as List<String>).map(displaySafe).join(' -> ');
      buffer.writeln('$prefix Circular script reference detected: $cycle.');

    case ErrorCode.missingScripts:
      buffer.writeln(
        '$prefix Field `scripts` is not defined in `pubspec.yaml`.',
      );

    case ErrorCode.invalidScripts:
      buffer.writeln('$prefix Type of field `scripts` is invalid.');
      buffer.writeln('$prefix It should be a map of scripts or a file path.');

    case ErrorCode.fileNotFound:
      final filePath = e.body['path'] as String;
      buffer.writeln('$prefix File not found at "${displaySafe(filePath)}".');

    case ErrorCode.invalidYaml:
      final filePath = e.body['path'] as String;
      final origin = e.body['origin'] as Object;

      buffer.writeln('$prefix Incorrect YAML format in "${displaySafe(filePath)}".');
      buffer.writeln('$prefix Origin ${displaySafeLines('$origin')}');

    case ErrorCode.invalidYamlMap:
      final filePath = e.body['path'] as String;
      buffer.writeln('$prefix YAML is not a map in "${displaySafe(filePath)}".');

    case ErrorCode.platformNotSupported:
      final abi = e.body['abi'] as String?;

      buffer.writeln('$prefix Unsupported plaform.');
      buffer.writeln('$prefix Architecture "${displaySafe('$abi')}" is not supported.');

    case ErrorCode.invalidPackageUri:
      final packageUri = e.body['packageUri'] as String;

      buffer.writeln('$prefix Unable to resolve package URI "${displaySafe(packageUri)}".');

    case ErrorCode.invalidBlob:
      final path = e.body['path'] as String;
      final origin = e.body['origin'] as Object;

      buffer.writeln('$prefix Unable to load dynamic library blob at "${displaySafe(path)}".');
      buffer.writeln('$prefix Origin ${displaySafeLines('$origin')}');
  }

  stderr.write(buffer.toString());
}
