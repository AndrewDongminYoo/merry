import 'dart:io' show Directory, File, IOOverrides, Platform;

import 'package:merry/error.dart';
import 'package:merry/utils.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

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
          'baz': [],
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
            'baz': {'bar': 'foo', 'baz': []},
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

      expect(jsonmap.getPaths(), equals(['bar', 'foo']));
    });
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

        await Future.delayed(const Duration(seconds: 1));

        // if scripts field is of a type other than Map or String
        final pubspecInvalidSource = Pubspec();
        (await pubspecInvalidSource.getContent())[scriptsKey] = 0;
        expect(
          pubspecInvalidSource.getSource(),
          throwsA(equals(MerryError(type: ErrorCode.invalidScripts))),
        );

        await Future.delayed(const Duration(seconds: 1));

        // if scripts field is a Map
        final pubspecMapSource = Pubspec();
        (await pubspecMapSource.getContent())[scriptsKey] = {};
        expect(await pubspecMapSource.getSource(), equals(pubspecFileName));

        // if scripts field is a string
        final pubspecFileSource = Pubspec();
        (await pubspecFileSource.getContent())[scriptsKey] = "merry.yaml";
        expect(await pubspecFileSource.getSource(), equals("merry.yaml"));

        // getScripts
        // if scripts field is a map
        final pubspecMapScripts = Pubspec();
        (await pubspecMapScripts.getContent())[scriptsKey] = {};
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
      final result = applyPositionalArgs('echo \$1 \$2', 'hello world');
      expect(result.key, equals('echo hello world'));
      expect(result.value, equals(''));
    });

    test('leaves script unchanged when no \$N tokens present', () {
      final result = applyPositionalArgs('echo hello', 'world');
      expect(result.key, equals('echo hello'));
      expect(result.value, equals('world'));
    });

    test('returns remaining unused args', () {
      final result = applyPositionalArgs('echo \$1', 'hello world');
      expect(result.key, equals('echo hello'));
      expect(result.value, equals('world'));
    });

    test('replaces out-of-range token with empty string', () {
      final result = applyPositionalArgs('echo \$1 \$2', 'hello');
      expect(result.key, equals('echo hello '));
      expect(result.value, equals(''));
    });

    test('handles empty extra', () {
      final result = applyPositionalArgs('echo \$1', '');
      expect(result.key, equals('echo '));
      expect(result.value, equals(''));
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
  });

  test("Reference's from factory should work", () {
    expect(
      Reference.from("\$script_a"),
      equals(const Reference(script: "script_a", extra: "")),
    );

    expect(
      Reference.from("\$script_a --extra extra"),
      equals(const Reference(script: "script_a", extra: "--extra extra")),
    );

    expect(
      Reference.from("\$script_a:script_b"),
      equals(const Reference(script: "script_a script_b", extra: "")),
    );
    expect(
      Reference.from("\$script_a:script_b --extra extra"),
      equals(
        const Reference(script: "script_a script_b", extra: "--extra extra"),
      ),
    );
  });

  group('ScriptsRegistry class', () {
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

      final invalidMapRegistry = ScriptsRegistry({"script_d": {}});
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

    // todo: to add tests for runScript
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
