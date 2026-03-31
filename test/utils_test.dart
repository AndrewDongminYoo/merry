import 'dart:convert' show jsonDecode;
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

      expect(jsonmap.getPaths(), equals(['foo bar', 'foo baz', 'bar']));
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
        equals(['foo bar', 'foo baz', 'foo buzz', 'bar']),
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
        equals(['foo bar baz bar', 'foo bar baz baz', 'bar']),
      );
    });

    test('getPaths should ignore keys with parenthesis', () {
      final jsonmap = {
        'foo': {'(bar)': 'baz', '(baz)': 'bar'},
        'bar': 'foo',
      };

      expect(jsonmap.getPaths(), equals(['foo', 'bar']));
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
        final pubspec = Pubspec();

        // filePath
        when(
          mockCurrentDirectory.uri,
        ).thenReturn(Uri.file("current-directory-path"));
        when(mockCurrentDirectory.path).thenReturn("current-directory-path");
        expect(
          Pubspec.filePath,
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

        expect(Pubspec.content, equals(null));
        expect(await pubspec.getContent(), equals(mockPubspecMap));
        expect(Pubspec.content, mockPubspecMap);

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
        expect(Pubspec.source, equals(null));
        expect(
          pubspec.getSource(),
          throwsA(equals(MerryError(type: ErrorCode.missingScripts))),
        );

        await Future.delayed(const Duration(seconds: 1));

        // if scripts field is of a type other than Map or String
        Pubspec.content![scriptsKey] = 0;
        expect(
          pubspec.getSource(),
          throwsA(equals(MerryError(type: ErrorCode.invalidScript))),
        );

        await Future.delayed(const Duration(seconds: 1));

        // if scripts field is a Map
        expect(Pubspec.source, equals(null));
        Pubspec.content![scriptsKey] = {};
        expect(await pubspec.getSource(), equals(pubspecFileName));
        expect(Pubspec.source, pubspecFileName);

        // if scripts field is a string
        Pubspec.source = null;
        Pubspec.content![scriptsKey] = "merry.yaml";
        expect(await pubspec.getSource(), equals("merry.yaml"));
        expect(Pubspec.source, "merry.yaml");

        // getScripts
        expect(Pubspec.scripts, equals(null));

        // if scripts field is a map
        Pubspec.scripts = null;
        Pubspec.source = pubspecFileName;
        expect(await pubspec.getScripts(), equals({}));
        expect(Pubspec.scripts, equals({}));

        // if scripts field is a string aka a file path
        Pubspec.scripts = null;
        Pubspec.source = "merry.yaml";

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

        expect(await pubspec.getScripts(), equals(mockScriptsMap));
        expect(Pubspec.scripts, equals(mockScriptsMap));
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
    late ScriptsRegistry registry;
    final sampleScriptsMap = {"script_a": "a"};

    setUp(() {
      ScriptsRegistry.scripts = null;
      ScriptsRegistry.paths = null;
      ScriptsRegistry.searchResults = {};
      ScriptsRegistry.serializedDefinitions = {};
      ScriptsRegistry.references = {};
      ScriptsRegistry.variables = null;
      ScriptsRegistry.aliasMap = null;
      registry = ScriptsRegistry(sampleScriptsMap);
    });

    test("constructor works", () {
      expect(ScriptsRegistry.scripts, equals(sampleScriptsMap));
    });

    test("getPaths memoization works", () {
      expect(ScriptsRegistry.paths, equals(null));
      expect(registry.getPaths(), equals(["script_a"]));
      expect(ScriptsRegistry.paths, equals(["script_a"]));
    });

    test("lookup memoization works", () {
      expect(ScriptsRegistry.searchResults, equals({}));
      expect(registry.lookup("script_a"), equals(sampleScriptsMap["script_a"]));
      expect(ScriptsRegistry.searchResults, equals(sampleScriptsMap));
    });

    test("getDefinition memoization works", () {
      expect(ScriptsRegistry.serializedDefinitions, equals({}));
      expect(
        registry.getDefinition("script_a"),
        equals(Definition.from(sampleScriptsMap["script_a"])),
      );
      expect(
        ScriptsRegistry.serializedDefinitions["script_a"],
        equals(Definition.from(sampleScriptsMap["script_a"])),
      );
    });

    test("getDefinition errors throw", () {
      // when script doesn't exist at all
      expect(
        () => registry.getDefinition("script_b"),
        throwsA(
          equals(
            MerryError(
              type: ErrorCode.scriptNotDefined,
              body: {'script': "script_b", 'suggestions': registry.getPaths()},
            ),
          ),
        ),
      );

      // when script exist but of invalid type
      ScriptsRegistry.scripts = {"script_c": 0}; // force update for test
      expect(
        () => registry.getDefinition("script_c"),
        throwsA(
          equals(
            MerryError(
              type: ErrorCode.invalidScript,
              body: {'script': "script_c"},
            ),
          ),
        ),
      );
      ScriptsRegistry.scripts = sampleScriptsMap; // reset

      // when script is valid but the map it points to is invalid
      // when (scripts) is null
      ScriptsRegistry.scripts = {"script_d": {}}; // force update for test
      expect(
        () => registry.getDefinition("script_d"),
        throwsA(
          equals(
            MerryError(
              type: ErrorCode.invalidScript,
              body: {'script': "script_d", 'paths': registry.getPaths()},
            ),
          ),
        ),
      );

      // when (scripts) is not a List or String
      ScriptsRegistry.scripts = {
        "script_e": {
          [scriptsDefinitionKey]: 0,
        },
      }; // force update for test
      expect(
        () => registry.getDefinition("script_e"),
        throwsA(
          equals(
            MerryError(
              type: ErrorCode.invalidScript,
              body: {'script': "script_e", 'paths': registry.getPaths()},
            ),
          ),
        ),
      );

      ScriptsRegistry.scripts = sampleScriptsMap; // reset
    });

    test("getDefinition uses (default) for nested command groups", () {
      ScriptsRegistry.scripts = {
        "group": {defaultDefinitionKey: "echo default", "sub": "echo sub"},
      };
      ScriptsRegistry.serializedDefinitions.remove("group");
      expect(
        registry.getDefinition("group"),
        equals(Definition.from("echo default")),
      );
      ScriptsRegistry.scripts = sampleScriptsMap;
      ScriptsRegistry.serializedDefinitions.remove("group");
    });

    test("getDefinition selects platform-specific script", () {
      final platformKey = Platform.isLinux
          ? linuxDefinitionKey
          : Platform.isMacOS
          ? macosDefinitionKey
          : windowsDefinitionKey;

      ScriptsRegistry.scripts = {
        "script_p": {
          platformKey: "echo platform",
          scriptsDefinitionKey: "echo fallback",
        },
      };
      ScriptsRegistry.serializedDefinitions.remove("script_p");

      expect(
        registry.getDefinition("script_p"),
        equals(Definition.from("echo platform")),
      );

      ScriptsRegistry.scripts = sampleScriptsMap;
      ScriptsRegistry.serializedDefinitions.remove("script_p");
    });

    test("getReference memoization works", () {
      expect(ScriptsRegistry.references, equals({}));
      expect(
        registry.getReference("\$script_a"),
        equals(Reference.from("\$script_a")),
      );
      expect(
        ScriptsRegistry.references["\$script_a"],
        equals(Reference.from("\$script_a")),
      );
    });

    test("getAliasMap collects top-level aliases", () {
      ScriptsRegistry.scripts = {
        "install": {
          aliasesDefinitionKey: ["i", "in"],
          scriptsDefinitionKey: "dart pub get",
        },
      };
      ScriptsRegistry.aliasMap = null;

      expect(registry.getAliasMap(), equals({"i": "install", "in": "install"}));

      ScriptsRegistry.scripts = sampleScriptsMap;
      ScriptsRegistry.aliasMap = null;
    });

    test("getAliasMap collects nested aliases", () {
      ScriptsRegistry.scripts = {
        "platform": {
          "linux": {
            aliasesDefinitionKey: "lin",
            scriptsDefinitionKey: "echo linux",
          },
        },
      };
      ScriptsRegistry.aliasMap = null;

      expect(
        registry.getAliasMap(),
        equals({"platform lin": "platform linux"}),
      );

      ScriptsRegistry.scripts = sampleScriptsMap;
      ScriptsRegistry.aliasMap = null;
    });

    test("getAliasMap handles string alias (not list)", () {
      ScriptsRegistry.scripts = {
        "install": {
          aliasesDefinitionKey: "i",
          scriptsDefinitionKey: "dart pub get",
        },
      };
      ScriptsRegistry.aliasMap = null;

      expect(registry.getAliasMap(), equals({"i": "install"}));

      ScriptsRegistry.scripts = sampleScriptsMap;
      ScriptsRegistry.aliasMap = null;
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

    test('JSON-encoded script entry matches expected schema', () {
      final def = Definition.from(const {
        descriptionDefinitionKey: 'Build the project',
        scriptsDefinitionKey: 'dart run build_runner build',
      });

      final entry = <String, dynamic>{'path': 'build', 'commands': def.scripts};
      if (def.description != null) entry['description'] = def.description;
      if (def.workdir != null) entry['workdir'] = def.workdir;

      final decoded =
          jsonDecode('{"path":"build","commands":["dart run build_runner build"],"description":"Build the project"}')
              as Map<String, dynamic>;

      expect(entry['path'], equals(decoded['path']));
      expect(entry['commands'], equals(decoded['commands']));
      expect(entry['description'], equals(decoded['description']));
      expect(entry.containsKey('workdir'), isFalse);
    });

    test('workdir field is omitted when null', () {
      final def = Definition.from('echo hi');
      final entry = <String, dynamic>{'path': 'greet', 'commands': def.scripts};
      if (def.workdir != null) entry['workdir'] = def.workdir;
      expect(entry.containsKey('workdir'), isFalse);
    });

    test('workdir field is present when set', () {
      final def = Definition.from(const {
        scriptsDefinitionKey: 'cargo build',
        workdirDefinitionKey: 'native',
      });
      final entry = <String, dynamic>{'path': 'native', 'commands': def.scripts};
      if (def.workdir != null) entry['workdir'] = def.workdir;
      expect(entry['workdir'], equals('native'));
    });
  });
}
