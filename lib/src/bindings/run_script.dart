import 'dart:ffi' as ffi;
import 'dart:isolate' show Isolate;

import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, malloc;
import 'package:merry/error.dart' show ErrorCode, MerryError;
import 'package:path/path.dart' as path;

const packageUri = 'package:merry/merry.dart';
const blobsPath = 'src/blobs/';

/// Supported operating systems with architectures
/// mapped to blob file extensions.
const supported = <ffi.Abi, String>{
  ffi.Abi.windowsX64: 'windows_x64.dll',
  ffi.Abi.linuxX64: 'linux_x64.so',
  ffi.Abi.macosX64: 'macos_x64.dylib',
  ffi.Abi.macosArm64: 'macos_arm64.dylib',
};

/// Gets the file name of blob files based on platform
///
/// File name doesn't contain directory paths.
String getBlobFilename() {
  final currentAbi = ffi.Abi.current();

  if (!supported.containsKey(currentAbi)) {
    throw MerryError(
      type: ErrorCode.platformNotSupported,
      body: {'abi': currentAbi},
    );
  }

  return supported[currentAbi]!;
}

typedef _RunScriptDart =
    int Function(
      ffi.Pointer<Utf8> script,
      ffi.Pointer<ffi.Pointer<Utf8>> argv,
      int argc,
      ffi.Pointer<ffi.Pointer<Utf8>> envKeys,
      ffi.Pointer<ffi.Pointer<Utf8>> envValues,
      int envCount,
    );

/// Marshals [items] into a C array of NUL-terminated strings. An empty list
/// maps to `nullptr`, which the native side reads as "no entries".
ffi.Pointer<ffi.Pointer<Utf8>> _toCArray(List<String> items) {
  if (items.isEmpty) return ffi.nullptr;
  final array = malloc<ffi.Pointer<Utf8>>(items.length);
  for (var i = 0; i < items.length; i++) {
    array[i] = items[i].toNativeUtf8();
  }
  return array;
}

/// Frees a C array previously built by [_toCArray], including its strings.
void _freeCArray(ffi.Pointer<ffi.Pointer<Utf8>> array, int count) {
  if (array == ffi.nullptr) return;
  for (var i = 0; i < count; i++) {
    malloc.free(array[i]);
  }
  malloc.free(array);
}

/// Run [script] in the platform shell via Dart FFI.
///
/// On POSIX, [args] are passed as the shell's own positional parameters
/// (`$1`, `$2`, …) and [env] entries are exported for `${VAR}` expansion, so
/// the script keeps its literal `$N`/`${VAR}` tokens and untrusted values are
/// never spliced into shell source. `cmd /C` cannot take positional parameters,
/// so on Windows the caller substitutes before calling and passes empty [args].
Future<int> runScript(
  String script, {
  List<String> args = const [],
  Map<String, String> env = const {},
}) async {
  final nativeRunScriptFn = await _resolveRunScriptFn();
  final scriptPtr = script.toNativeUtf8();
  final argvPtr = _toCArray(args);
  final keys = env.keys.toList();
  final values = env.values.toList();
  final keysPtr = _toCArray(keys);
  final valuesPtr = _toCArray(values);
  try {
    return nativeRunScriptFn(
      scriptPtr,
      argvPtr,
      args.length,
      keysPtr,
      valuesPtr,
      keys.length,
    );
  } finally {
    malloc.free(scriptPtr);
    _freeCArray(argvPtr, args.length);
    _freeCArray(keysPtr, keys.length);
    _freeCArray(valuesPtr, values.length);
  }
}

ffi.DynamicLibrary? _dylib;
Future<_RunScriptDart>? _initFuture;

// Returning the same Future for concurrent callers prevents double-initialization
// across await suspension points in Dart's single-threaded event loop.
Future<_RunScriptDart> _resolveRunScriptFn() => _initFuture ??= _initRunScriptFn();

Future<_RunScriptDart> _initRunScriptFn() async {
  final resolvedPackageUri = await Isolate.resolvePackageUri(
    Uri.parse(packageUri),
  );
  if (resolvedPackageUri == null) {
    throw MerryError(
      type: ErrorCode.invalidPackageUri,
      body: {'packageUri': packageUri},
    );
  }

  final objectFilePath = resolvedPackageUri.resolve(path.join(blobsPath, getBlobFilename())).toFilePath();
  try {
    _dylib ??= ffi.DynamicLibrary.open(objectFilePath);
  } catch (e) {
    throw MerryError(
      type: ErrorCode.invalidBlob,
      body: {'path': objectFilePath, 'origin': e},
    );
  }

  return _dylib!
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<Utf8> script,
            ffi.Pointer<ffi.Pointer<Utf8>> argv,
            ffi.IntPtr argc,
            ffi.Pointer<ffi.Pointer<Utf8>> envKeys,
            ffi.Pointer<ffi.Pointer<Utf8>> envValues,
            ffi.IntPtr envCount,
          )
        >
      >('run_script')
      .asFunction<_RunScriptDart>();
}
