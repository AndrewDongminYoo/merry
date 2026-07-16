import 'package:args/args.dart' show ArgResults;
import 'package:args/command_runner.dart' show UsageException;

/// Throws a [UsageException] when [argResults] carries positional arguments a
/// command takes no meaning from.
///
/// The message must never start with `Could not find a command named`, which
/// `runMerry` treats as the signal to re-dispatch through `run`.
void rejectRest(ArgResults argResults, String usage) {
  final rest = argResults.rest;
  if (rest.isNotEmpty) {
    throw UsageException('Unexpected argument(s): ${rest.join(' ')}', usage);
  }
}
