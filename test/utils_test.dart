import 'dart:io' show Directory, File, IOOverrides, Link, Platform;

import 'package:merry/error.dart';
import 'package:merry/utils.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart' show loadYaml;

@GenerateMocks([File, Directory])
import './utils_test.mocks.dart';

void main() {
  test("Definition's from factory should work", () {
    expect(
      Definition.from('echo 0'),
      equals(const Definition(scripts: ['echo 0'])),
    );

    expect(
      Definition.from(const ['echo 0', 'echo 1']),
      equals(const Definition(scripts: ['echo 0', 'echo 1'])),
    );

    expect(
      Definition.from(const {
        '(description)': 'A description',
        '(scripts)': ['echo 0', 'echo 1'],
      }),
      equals(
        const Definition(
          description: 'A description',
          scripts: ['echo 0', 'echo 1'],
        ),
      ),
    );

    expect(
      Definition.from(const {'(scripts)': 'echo 0', '(workdir)': '/tmp'}),
      equals(const Definition(scripts: ['echo 0'], workdir: '/tmp')),
    );

    expect(
      Definition.from(const {
        '(execution)': 'once',
        '(scripts)': ['exit 1', 'echo unsafe'],
      }),
      equals(
        const Definition(
          execution: 'once',
          scripts: ['exit 1', 'echo unsafe'],
        ),
      ),
    );
  });

  test("Definition.from rejects an unknown execution mode", () {
    // A typo must fail loudly instead of silently degrading to `multiple`,
    // which would run every command after a failure.
    expect(
      () => Definition.from(const {
        '(execution)': 'onc',
        '(scripts)': 'echo hi',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Definition.from(const {
        '(execution)': 'once ',
        '(scripts)': 'echo hi',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test("Definition.from defaults execution to multiple", () {
    expect(Definition.from('echo hi').execution, equals('multiple'));
    expect(
      Definition.from(const {'(scripts)': 'echo hi'}).execution,
      equals('multiple'),
    );
  });

  test("Info's toString should work", () {
    expect(
      const Info(name: 'merry', version: '0.0.1').toString(),
      equals('merry@0.0.1'),
    );
  });

  group("JsonMap's lookup function", () {
    final jsonmap = {
      'foo': {'bar': 'baz'},
    };

    test('lookup should return the correct value for a valid path', () {
      expect(jsonmap.lookup('foo bar'), equals('baz'));
    });

    test('lookup should return null for an invalid path', () {
      expect(jsonmap.lookup('foo baz'), isNull);
    });

    test('lookup should also be able to return maps', () {
      expect(jsonmap.lookup('foo'), equals({'bar': 'baz'}));
    });
  });

  group("JsonMap's getPaths function", () {
    test('getPaths should return all valid paths with string scripts', () {
      final jsonmap = {
        'foo': {'bar': 'baz', 'baz': 'bar'},
        'bar': 'foo',
      };

      expect(jsonmap.getPaths(), equals(['bar', 'foo bar', 'foo baz']));
    });

    test('getPaths should return all valid paths with array of scripts', () {
      final jsonmap = {
        'foo': {
          'bar': ['baz', 'bar'],
          'baz': <String>[],
          'buzz': ['foo'],
        },
        'bar': 'foo',
      };

      expect(
        jsonmap.getPaths(),
        equals(['bar', 'foo bar', 'foo baz', 'foo buzz']),
      );
    });

    test('getPaths should return all valid paths even when deeply nested', () {
      final jsonmap = {
        'foo': {
          'bar': {
            'baz': {'bar': 'foo', 'baz': <String>[]},
          },
        },
        'bar': 'foo',
      };

      expect(
        jsonmap.getPaths(),
        equals(['bar', 'foo bar baz bar', 'foo bar baz baz']),
      );
    });

    test('getPaths should ignore keys with parenthesis', () {
      final jsonmap = {
        'foo': {'(bar)': 'baz', '(baz)': 'bar'},
        'bar': 'foo',
      };

      // 'foo' holds no runnable script, only unknown metadata, so it is not a
      // path — listing it would make getDefinition throw invalidScript.
      expect(jsonmap.getPaths(), equals(['bar']));
    });

    test('getPaths should keep a group that is runnable and has sub-commands', () {
      final jsonmap = {
        'build': {
          '(default)': 'build all',
          'web': 'build web',
        },
        'test': {
          '(scripts)': 'test all',
          'unit': 'test unit',
        },
      };

      expect(
        jsonmap.getPaths(),
        equals(['build', 'build web', 'test', 'test unit']),
      );
    });

    test('getPaths should not list a group that only nests sub-commands', () {
      final jsonmap = {
        'build': {'web': 'build web'},
      };

      expect(jsonmap.getPaths(), equals(['build web']));
    });
  });

  test('toJsonMap rejects cyclic YAML aliases', () {
    final yaml = loadYaml('scripts: &scripts\n  loop: *scripts\n') as Map;

    expect(yaml.toJsonMap, throwsA(isA<FormatException>()));
  });

  test('toJsonMap rejects a cyclic anchor reused as a mapping key', () {
    // `? *foo` makes the mapping its own key; hashing that cyclic key
    // deep-recurses in package:yaml and would overflow the stack (crashing
    // e.g. `merry ls`) before any cycle check could run.
    final yaml = loadYaml('foo: &foo\n  ? *foo\n  : echo hi\n') as Map;

    expect(yaml.toJsonMap, throwsA(isA<FormatException>()));
  });

  // grouping a bunch of tests didn't work with IOOverrides
  // therefore we have a big test instead
  test('Pubspec class', () {
    final mockFile = MockFile();
    final mockDirectory = MockDirectory();
    final mockCurrentDirectory = MockDirectory();

    IOOverrides.runZoned(
      () async {
        // filePath
        when(
          mockCurrentDirectory.uri,
        ).thenReturn(Uri.file("current-directory-path"));
        when(mockCurrentDirectory.path).thenReturn("current-directory-path");
        when(
          mockDirectory.resolveSymbolicLinks(),
        ).thenAnswer((_) async => "current-directory-path");
        when(
          mockFile.resolveSymbolicLinks(),
        ).thenAnswer((_) async => path.join("current-directory-path", "merry.yaml"));

        final pubspec = Pubspec();

        expect(
          pubspec.filePath,
          equals(path.join("current-directory-path", pubspecFileName)),
        );

        // content
        const mockPubspecContent = """
name: test
version: 0.0.0""";
        const mockPubspecMap = {"name": "test", "version": "0.0.0"};
        when(mockFile.exists()).thenAnswer((_) => Future.value(true));
        when(
          mockFile.readAsString(),
        ).thenAnswer((_) => Future.value(mockPubspecContent));

        expect(await pubspec.getContent(), equals(mockPubspecMap));

        // getInfo
        expect(
          await pubspec.getInfo(),
          Info(
            name: mockPubspecMap["name"],
            version: mockPubspecMap["version"],
          ),
        );

        // getSource
        // if scripts field is null
        expect(
          pubspec.getSource(),
          throwsA(equals(MerryError(type: ErrorCode.missingScripts))),
        );

        await Future<void>.delayed(const Duration(seconds: 1));

        // if scripts field is of a type other than Map or String
        final pubspecInvalidSource = Pubspec();
        (await pubspecInvalidSource.getContent())[scriptsKey] = 0;
        expect(
          pubspecInvalidSource.getSource(),
          throwsA(equals(MerryError(type: ErrorCode.invalidScripts))),
        );

        await Future<void>.delayed(const Duration(seconds: 1));

        // if scripts field is a Map
        final pubspecMapSource = Pubspec();
        (await pubspecMapSource.getContent())[scriptsKey] = <String, dynamic>{};
        expect(await pubspecMapSource.getSource(), equals(pubspecFileName));

        // if scripts field is a string
        final pubspecFileSource = Pubspec();
        (await pubspecFileSource.getContent())[scriptsKey] = "merry.yaml";
        expect(await pubspecFileSource.getSource(), equals("merry.yaml"));

        // getScripts
        // if scripts field is a map
        final pubspecMapScripts = Pubspec();
        (await pubspecMapScripts.getContent())[scriptsKey] = <String, dynamic>{};
        expect(await pubspecMapScripts.getScripts(), equals({}));

        // if scripts field is a string aka a file path
        final pubspecFileScripts = Pubspec();
        (await pubspecFileScripts.getContent())[scriptsKey] = "merry.yaml";

        const mockScriptsFile = """
a: b
c:
  - d
  - e""";
        final mockScriptsMap = {
          "a": "b",
          "c": ["d", "e"],
        };
        when(mockFile.exists()).thenAnswer((_) => Future.value(true));
        when(
          mockFile.readAsString(),
        ).thenAnswer((_) => Future.value(mockScriptsFile));

        expect(await pubspecFileScripts.getScripts(), equals(mockScriptsMap));
      },
      getCurrentDirectory: () => mockCurrentDirectory,
      createDirectory: (path) => mockDirectory,
      createFile: (path) => mockFile,
    );
  });

  test('Pubspec rejects an absolute scripts file outside the project', () async {
    final project = await Directory.systemTemp.createTemp('merry-project-');
    final external = await Directory.systemTemp.createTemp('merry-external-');
    addTearDown(() async {
      await project.delete(recursive: true);
      await external.delete(recursive: true);
    });

    final scriptsFile = File(path.join(external.path, 'secrets.yaml'));
    await scriptsFile.writeAsString('token: secret');
    await File(path.join(project.path, pubspecFileName)).writeAsString('''
name: malicious
scripts: ${scriptsFile.path}
''');

    expect(
      Pubspec(currentDirPath: project.path).getScripts(),
      throwsA(equals(MerryError(type: ErrorCode.invalidScripts))),
    );
  });

  test('Pubspec rejects a scripts symlink outside the project', () async {
    final project = await Directory.systemTemp.createTemp('merry-project-');
    final external = await Directory.systemTemp.createTemp('merry-external-');
    addTearDown(() async {
      await project.delete(recursive: true);
      await external.delete(recursive: true);
    });

    final scriptsFile = File(path.join(external.path, 'secrets.yaml'));
    await scriptsFile.writeAsString('token: secret');
    await Link(path.join(project.path, 'merry.yaml')).create(scriptsFile.path);
    await File(path.join(project.path, pubspecFileName)).writeAsString('''
name: malicious
scripts: merry.yaml
''');

    expect(
      Pubspec(currentDirPath: project.path).getScripts(),
      throwsA(equals(MerryError(type: ErrorCode.invalidScripts))),
    );
  });

  group('Yaml file reading utilities', () {
    test("read_yaml_map should fail when there's not a file", () {
      expect(
        readYamlMap('yaml'),
        throwsA(
          equals(
            MerryError(type: ErrorCode.fileNotFound, body: {'path': 'yaml'}),
          ),
        ),
      );
    });

    test('read_yaml_map should fail when the file is not in yaml format', () {
      expect(readYamlMap('README.md'), throwsA(isA<MerryError>()));
    });
  });

  group('applyPositionalArgs', () {
    test('replaces \$1, \$2 with positional args', () {
      final result = applyPositionalArgs('echo \$1 \$2', ['hello', 'world']);
      expect(result.key, equals('echo hello world'));
      expect(result.value, isEmpty);
    });

    test('leaves script unchanged when no \$N tokens present', () {
      final result = applyPositionalArgs('echo hello', ['world']);
      expect(result.key, equals('echo hello'));
      expect(result.value, equals(['world']));
    });

    test('returns remaining unused args', () {
      final result = applyPositionalArgs('echo \$1', ['hello', 'world']);
      expect(result.key, equals('echo hello'));
      expect(result.value, equals(['world']));
    });

    test('replaces out-of-range token with empty string', () {
      final result = applyPositionalArgs('echo \$1 \$2', ['hello']);
      expect(result.key, equals('echo hello '));
      expect(result.value, isEmpty);
    });

    test('handles empty extra', () {
      final result = applyPositionalArgs('echo \$1', []);
      expect(result.key, equals('echo '));
      expect(result.value, isEmpty);
    });

    test('quotes an arg containing spaces so it stays a single argument', () {
      final result = applyPositionalArgs('greet \$1', ['Jane Doe']);
      expect(
        result.key,
        equals(Platform.isWindows ? 'greet "Jane Doe"' : "greet 'Jane Doe'"),
      );
      expect(result.value, isEmpty);
    });

    test('rejects a referenced arg that carries a shell-active character', () {
      // Fail-closed: a placeholder can sit inside quotes, where `$(...)` runs in
      // double quotes and `;` runs in single quotes, so refuse rather than
      // splice. (Only referenced args are checked; unused ones are appended in a
      // safe unquoted position.)
      expect(
        () => applyPositionalArgs('echo \$1', [r'$(touch pwned)']),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => applyPositionalArgs("echo '\$1'", ['; touch pwned']),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('collectVariables', () {
    test('collects top-level (variables)', () {
      expect(
        collectVariables({
          variablesDefinitionKey: {'OUTPUT': 'build', 'MODE': 'release'},
          'build': 'dart build',
        }),
        equals({'OUTPUT': 'build', 'MODE': 'release'}),
      );
    });

    test('collects nested (variables)', () {
      expect(
        collectVariables({
          'group': {
            variablesDefinitionKey: {'DIR': 'packages/ui'},
            scriptsDefinitionKey: 'echo done',
          },
        }),
        equals({'DIR': 'packages/ui'}),
      );
    });

    test('later definitions override earlier ones', () {
      expect(
        collectVariables({
          variablesDefinitionKey: {'X': 'top'},
          'group': {
            variablesDefinitionKey: {'X': 'nested'},
            scriptsDefinitionKey: 'echo hi',
          },
        }),
        equals({'X': 'nested'}),
      );
    });
  });

  group('substituteVariables', () {
    test('replaces \${VAR} with value from map', () {
      expect(
        substituteVariables('dart build --output \${OUTPUT}', {
          'OUTPUT': 'build',
        }),
        equals('dart build --output build'),
      );
    });

    test('leaves unknown \${VAR} unchanged when not in env', () {
      expect(
        substituteVariables('echo \${UNKNOWN_VAR_XYZ}', {}),
        equals('echo \${UNKNOWN_VAR_XYZ}'),
      );
    });

    test('map value takes precedence over environment', () {
      expect(
        substituteVariables('echo \${PATH}', {'PATH': 'overridden'}),
        equals('echo overridden'),
      );
    });

    test('rejects a variable value that carries a shell-active character', () {
      // (variables) values are spliced as text, so a `$(...)` or `;` payload
      // must fail closed rather than reach the shell.
      expect(
        () => substituteVariables('echo \${V}', {'V': r'$(touch pwned)'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => substituteVariables('echo \${V}', {'V': '; rm -rf /'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test("Reference's from factory should work", () {
    expect(
      Reference.from("\$script_a"),
      equals(const Reference(script: "script_a", extra: [])),
    );

    expect(
      Reference.from("\$script_a --extra extra"),
      equals(const Reference(script: "script_a", extra: ["--extra", "extra"])),
    );

    expect(
      Reference.from("\$script_a:script_b"),
      equals(const Reference(script: "script_a script_b", extra: [])),
    );
    expect(
      Reference.from("\$script_a:script_b --extra extra"),
      equals(
        const Reference(script: "script_a script_b", extra: ["--extra", "extra"]),
      ),
    );
  });

  test("Reference's from factory keeps quoted extras as one argument", () {
    final reference = Reference.from('\$deploy --message "hello world"');
    expect(reference.script, equals('deploy'));
    expect(reference.extra, equals(['--message', 'hello world']));

    // shellQuote round-trips it back into a single shell argument
    expect(
      reference.extra.map(shellQuote).join(' '),
      equals(Platform.isWindows ? '--message "hello world"' : "--message 'hello world'"),
    );
  });

  test('shellChangeDirectory treats the workdir as literal data', () {
    const workdir = r'$(touch /tmp/pwn)';

    expect(
      shellChangeDirectory(workdir),
      equals(
        Platform.isWindows ? r'cd /d "$(touch /tmp/pwn)" &&' : r"cd '$(touch /tmp/pwn)' &&",
      ),
    );
  });

  group('shellSplit', () {
    test('splits on whitespace', () {
      expect(shellSplit('a b\tc'), equals(['a', 'b', 'c']));
    });

    test('keeps quoted runs together', () {
      expect(shellSplit('--m "hello world"'), equals(['--m', 'hello world']));
      expect(shellSplit("--m 'hello world'"), equals(['--m', 'hello world']));
    });

    test('joins quotes adjacent to a word', () {
      expect(shellSplit('--m="hello world"'), equals(['--m=hello world']));
    });

    test('keeps an empty quoted string as a word', () {
      expect(shellSplit("a '' b"), equals(['a', '', 'b']));
    });

    test('treats a backslash as an escape off Windows', () {
      expect(
        shellSplit(r'hello\ world'),
        equals(Platform.isWindows ? [r'hello\', 'world'] : ['hello world']),
      );
    });

    test('keeps a backslash literal inside single quotes', () {
      expect(shellSplit(r"'hello\ world'"), equals([r'hello\ world']));
    });

    test('takes an unterminated quote as the rest of the input', () {
      expect(shellSplit('a "b c'), equals(['a', 'b c']));
    });

    test('returns no words for an empty or blank input', () {
      expect(shellSplit(''), isEmpty);
      expect(shellSplit('   '), isEmpty);
    });
  });

  group('ScriptsRegistry class', () {
    test('(execution): once stops after the first failed script', () async {
      // Exercised through the injected runner like the pre-hook tests: under
      // `dart test` the native blob returns a spurious failure for every real
      // command, so a shell-backed exit code cannot be asserted here.
      final ran = <String>[];
      final registry = ScriptsRegistry(
        {
          'release': {
            executionDefinitionKey: 'once',
            scriptsDefinitionKey: ['exit 7', 'echo unsafe'],
          },
        },
        runCommand: (cmd) async {
          ran.add(cmd);
          return cmd.contains('exit 7') ? 7 : 0;
        },
      );

      expect(await registry.runScript('release'), equals(7));
      // Fail-fast: the once list stops at the first failure, so the second
      // command that would have run the unsafe side effect never executes.
      expect(ran, equals(['exit 7']));
    });

    test("constructor works", () {
      final sampleScriptsMap = {"script_a": "a"};
      final registry = ScriptsRegistry(sampleScriptsMap);
      expect(registry.getPaths(), equals(["script_a"]));
    });

    test("lookup and getDefinition work", () {
      final sampleScriptsMap = {"script_a": "a"};
      final registry = ScriptsRegistry(sampleScriptsMap);
      expect(registry.lookup("script_a"), equals("a"));
      expect(registry.getDefinition("script_a"), equals(Definition.from("a")));
    });

    test("getDefinition errors throw", () {
      final registry = ScriptsRegistry({"script_a": "a"});
      expect(
        () => registry.getDefinition("script_b"),
        throwsA(isA<MerryError>()),
      );

      final invalidTypeRegistry = ScriptsRegistry({"script_c": 0});
      expect(
        () => invalidTypeRegistry.getDefinition("script_c"),
        throwsA(isA<MerryError>()),
      );

      final invalidMapRegistry = ScriptsRegistry({"script_d": <String, dynamic>{}});
      expect(
        () => invalidMapRegistry.getDefinition("script_d"),
        throwsA(isA<MerryError>()),
      );
    });

    test("getDefinition uses (default) for nested command groups", () {
      final registry = ScriptsRegistry({
        "group": {defaultDefinitionKey: "echo default", "sub": "echo sub"},
      });
      expect(
        registry.getDefinition("group"),
        equals(Definition.from("echo default")),
      );
    });

    test("getDefinition selects platform-specific script", () {
      final platformKey = Platform.isLinux
          ? linuxDefinitionKey
          : Platform.isMacOS
          ? macosDefinitionKey
          : windowsDefinitionKey;

      final registry = ScriptsRegistry({
        "script_p": {
          platformKey: "echo platform",
          scriptsDefinitionKey: "echo fallback",
        },
      });

      expect(
        registry.getDefinition("script_p"),
        equals(Definition.from("echo platform")),
      );
    });

    test("getDefinition keeps surrounding metadata for a platform script", () {
      final platformKey = Platform.isLinux
          ? linuxDefinitionKey
          : Platform.isMacOS
          ? macosDefinitionKey
          : windowsDefinitionKey;

      final registry = ScriptsRegistry({
        "script_p": {
          platformKey: "echo platform",
          workdirDefinitionKey: "packages/app",
          descriptionDefinitionKey: "a platform script",
        },
      });

      expect(
        registry.getDefinition("script_p"),
        equals(
          const Definition(
            scripts: ["echo platform"],
            workdir: "packages/app",
            description: "a platform script",
          ),
        ),
      );
    });

    test("getDefinition keeps surrounding metadata for a (default) script", () {
      final registry = ScriptsRegistry({
        "group": {
          defaultDefinitionKey: "echo default",
          workdirDefinitionKey: "packages/app",
          "sub": "echo sub",
        },
      });

      expect(
        registry.getDefinition("group"),
        equals(
          const Definition(scripts: ["echo default"], workdir: "packages/app"),
        ),
      );
    });

    test("getReference memoization works", () {
      final registry = ScriptsRegistry({"script_a": "a"});
      expect(
        registry.getReference("\$script_a"),
        equals(Reference.from("\$script_a")),
      );
      expect(
        registry.getReference("\$script_a"),
        equals(Reference.from("\$script_a")),
      );
    });

    test("getAliasMap collects top-level aliases", () {
      final registry = ScriptsRegistry({
        "install": {
          aliasesDefinitionKey: ["i", "in"],
          scriptsDefinitionKey: "dart pub get",
        },
      });

      expect(registry.getAliasMap(), equals({"i": "install", "in": "install"}));
    });

    test("getAliasMap collects nested aliases", () {
      final registry = ScriptsRegistry({
        "platform": {
          "linux": {
            aliasesDefinitionKey: "lin",
            scriptsDefinitionKey: "echo linux",
          },
        },
      });

      expect(
        registry.getAliasMap(),
        equals({"platform lin": "platform linux"}),
      );
    });

    test("getAliasMap handles string alias (not list)", () {
      final registry = ScriptsRegistry({
        "install": {
          aliasesDefinitionKey: "i",
          scriptsDefinitionKey: "dart pub get",
        },
      });

      expect(registry.getAliasMap(), equals({"i": "install"}));
    });

    test("runScript propagates SIGINT (130) from a post-hook", () async {
      // A Ctrl+C in a post<name> hook must not be masked by the main script's
      // success: a $-reference parent would otherwise receive 0 and continue.
      final registry = ScriptsRegistry(
        {"build": "echo build", "postbuild": "echo cancelled"},
        runCommand: (cmd) async => cmd.contains("cancelled") ? 130 : 0,
      );
      expect(await registry.runScript("build"), equals(130));
    });

    test("runScript propagates SIGINT (130) from a pre-hook", () async {
      final registry = ScriptsRegistry(
        {"prebuild": "echo cancelled", "build": "echo build"},
        runCommand: (cmd) async => cmd.contains("cancelled") ? 130 : 0,
      );
      expect(await registry.runScript("build"), equals(130));
    });

    test("runScript returns the main exit code when hooks succeed", () async {
      final registry = ScriptsRegistry(
        {"prebuild": "echo pre", "build": "exit 7", "postbuild": "echo post"},
        runCommand: (cmd) async => cmd.contains("exit 7") ? 7 : 0,
      );
      expect(await registry.runScript("build"), equals(7));
    });

    test("runScript stops when its pre-hook fails", () async {
      final directory = Directory.systemTemp.createTempSync(
        'merry-pre-hook-test-',
      );
      final marker = File(path.join(directory.path, 'main-ran'));
      final registry = ScriptsRegistry({
        "predeploy": "dart definitely-not-a-command",
        "deploy": "echo ran > ${shellQuote(marker.path)}",
      });

      try {
        final exitCode = await registry.runScript("deploy");

        expect(exitCode, isNot(0));
        expect(marker.existsSync(), isFalse);
      } finally {
        directory.deleteSync(recursive: true);
      }
    });

    test("runScript aborts when a list-valued pre-hook fails mid-list", () async {
      // A failing validation followed by a would-be cleanup (the documented
      // prepublish-list form): the failure must not be masked by the later
      // command's success, or the protected script runs anyway.
      final ran = <String>[];
      final registry = ScriptsRegistry(
        {
          "predeploy": ["exit 2", "echo cleanup"],
          "deploy": "echo main",
        },
        runCommand: (cmd) async {
          ran.add(cmd);
          return cmd.contains("exit 2") ? 2 : 0;
        },
      );

      final exitCode = await registry.runScript("deploy");

      expect(exitCode, equals(2));
      // Fail-fast: the list stops at the first failure, so the cleanup and the
      // main script (reached only after a zero-status pre-hook) never run.
      expect(ran, equals(["exit 2"]));
    });

    test("(execution): multiple runs every command after a plain failure", () async {
      // The Definition contract is "`multiple` to run every script": a plain
      // non-zero exit must not stop the list. Guards the once-vs-multiple call.
      final ran = <String>[];
      final registry = ScriptsRegistry(
        {
          "check": {
            executionDefinitionKey: "multiple",
            scriptsDefinitionKey: ["fail lint", "run other"],
          },
        },
        runCommand: (cmd) async {
          ran.add(cmd);
          return cmd.contains("fail") ? 7 : 0;
        },
      );

      final exitCode = await registry.runScript("check");

      // Runs all; the exit code is the last command's, not the earlier failure.
      expect(exitCode, equals(0));
      expect(ran, equals(["fail lint", "run other"]));
    });

    test("(execution): multiple still stops the list on a SIGINT (130)", () async {
      // Ctrl+C must end the sequence even in multiple mode, unlike a plain
      // failure. Guards the `exitCode == _sigintExitCode` clause of the break.
      final ran = <String>[];
      final registry = ScriptsRegistry(
        {
          "check": {
            executionDefinitionKey: "multiple",
            scriptsDefinitionKey: ["cancelled step", "run other"],
          },
        },
        runCommand: (cmd) async {
          ran.add(cmd);
          return cmd.contains("cancelled") ? 130 : 0;
        },
      );

      final exitCode = await registry.runScript("check");

      expect(exitCode, equals(130));
      expect(ran, equals(["cancelled step"]));
    });
  });

  group('ls --output=json shape', () {
    // These tests verify the data that the JSON output of `merry ls` is built
    // from, without invoking the command itself (which writes directly to stdout).

    test('simple string script produces single-element commands list', () {
      final def = Definition.from('dart test');
      expect(def.scripts, equals(['dart test']));
      expect(def.description, isNull);
      expect(def.workdir, isNull);
    });

    test('map script with metadata produces correct definition fields', () {
      final def = Definition.from(const {
        descriptionDefinitionKey: 'Run tests',
        scriptsDefinitionKey: ['dart test', 'echo done'],
        workdirDefinitionKey: '/tmp',
      });
      expect(def.scripts, equals(['dart test', 'echo done']));
      expect(def.description, equals('Run tests'));
      expect(def.workdir, equals('/tmp'));
    });

    test('entry uses name field (not path)', () {
      final def = Definition.from(const {
        descriptionDefinitionKey: 'Build the project',
        scriptsDefinitionKey: 'dart run build_runner build',
      });

      final entry = <String, dynamic>{'name': 'build', 'commands': def.scripts};
      if (def.description != null) entry['description'] = def.description;
      if (def.workdir != null) entry['workdir'] = def.workdir;

      expect(entry['name'], equals('build'));
      expect(entry['commands'], equals(['dart run build_runner build']));
      expect(entry['description'], equals('Build the project'));
      expect(entry.containsKey('workdir'), isFalse);
      expect(entry.containsKey('path'), isFalse);
    });

    test('workdir field is omitted when null', () {
      final def = Definition.from('echo hi');
      final entry = <String, dynamic>{'name': 'greet', 'commands': def.scripts};
      if (def.workdir != null) entry['workdir'] = def.workdir;
      expect(entry.containsKey('workdir'), isFalse);
    });

    test('workdir field is present when set', () {
      final def = Definition.from(const {
        scriptsDefinitionKey: 'cargo build',
        workdirDefinitionKey: 'native',
      });
      final entry = <String, dynamic>{'name': 'native', 'commands': def.scripts};
      if (def.workdir != null) entry['workdir'] = def.workdir;
      expect(entry['workdir'], equals('native'));
    });

    test('execution field is omitted when default (multiple)', () {
      final def = Definition.from('echo hi');
      final entry = <String, dynamic>{'name': 'greet', 'commands': def.scripts};
      if (def.execution != 'multiple') entry['execution'] = def.execution;
      expect(entry.containsKey('execution'), isFalse);
    });

    test('execution field is present when set to once', () {
      final def = Definition.from(const {
        executionDefinitionKey: 'once',
        scriptsDefinitionKey: ['build', 'deploy'],
      });
      final entry = <String, dynamic>{'name': 'ship', 'commands': def.scripts};
      if (def.execution != 'multiple') entry['execution'] = def.execution;
      expect(entry['execution'], equals('once'));
    });

    test('hooks field lists pre/post script names when they exist', () {
      final names = ['build', 'postbuild', 'prebuild'];
      final nameSet = names.toSet();

      Map<String, dynamic> buildEntry(String name) {
        final entry = <String, dynamic>{'name': name};
        final hooks = <String, String>{};
        if (nameSet.contains('pre$name')) hooks['pre'] = 'pre$name';
        if (nameSet.contains('post$name')) hooks['post'] = 'post$name';
        if (hooks.isNotEmpty) entry['hooks'] = hooks;
        if (name.startsWith('pre') && name.length > 3) {
          final base = name.substring(3);
          if (nameSet.contains(base)) entry['hook_for'] = base;
        } else if (name.startsWith('post') && name.length > 4) {
          final base = name.substring(4);
          if (nameSet.contains(base)) entry['hook_for'] = base;
        }
        return entry;
      }

      final scriptEntry = buildEntry('build');
      expect(scriptEntry['hooks'], equals({'pre': 'prebuild', 'post': 'postbuild'}));
      expect(scriptEntry.containsKey('hook_for'), isFalse);

      final preEntry = buildEntry('prebuild');
      expect(preEntry.containsKey('hooks'), isFalse);
      expect(preEntry['hook_for'], equals('build'));

      final postEntry = buildEntry('postbuild');
      expect(postEntry.containsKey('hooks'), isFalse);
      expect(postEntry['hook_for'], equals('build'));
    });

    test('hook_for is not set when base script does not exist', () {
      // "preview" starts with "pre" but "view" does not exist as a script
      final nameSet = {'preview', 'test'};
      const name = 'preview';
      final entry = <String, dynamic>{'name': name};
      if (name.startsWith('pre') && name.length > 3) {
        final base = name.substring(3);
        if (nameSet.contains(base)) entry['hook_for'] = base;
      }
      expect(entry.containsKey('hook_for'), isFalse);
    });
  });
}
