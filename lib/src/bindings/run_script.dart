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

/// Run a given input string in console in native code via dart ffi
Future<int> runScript(String script) async {
  final nativeRunScriptFn = await _resolveRunScriptFn();
  final scriptPtr = script.toNativeUtf8();
  try {
    return nativeRunScriptFn(scriptPtr);
  } finally {
    malloc.free(scriptPtr);
  }
}

ffi.DynamicLibrary? _dylib;
Future<int Function(ffi.Pointer<Utf8>)>? _initFuture;

// Returning the same Future for concurrent callers prevents double-initialization
// across await suspension points in Dart's single-threaded event loop.
Future<int Function(ffi.Pointer<Utf8>)> _resolveRunScriptFn() => _initFuture ??= _initRunScriptFn();

Future<int Function(ffi.Pointer<Utf8>)> _initRunScriptFn() async {
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
      .lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<Utf8>)>>(
        'run_script',
      )
      .asFunction<int Function(ffi.Pointer<Utf8>)>();
}
