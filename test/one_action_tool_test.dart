import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tools_api/is_tools_api.dart';

/// [json] as it arrives over the wire.
JsonObject sent(JsonObject json) => .decode(jsonEncode(json));

enum Mode { list, stage }

void main() {
  final input = Input.fields7(
    Field('name', .string(minLength: 1), description: 'The file name.'),
    Field.orDefault('offset', .integer(minimum: 0), 0),
    Field.orDefault('mode', .choice(Mode.values), Mode.list),
    Field.optional('note', .string()),
    Field('tags', .list(.string())),
    Field('weight', .number()),
    Field('at', .object(.field(Field('line', .integer())))),
    (a, b, c, d, e, f, g) => (a, b, c, d, e, f, g),
  );
  OneActionTool readDocument({
    List<ActionArgument>? arguments,
    Map<String, Literal>? bound,
    String name = 'read_document',
    String action = 'readDocument',
  }) => .of(
    name: name,
    description: 'Reads a Word document.',
    input: input,
    bound: bound ?? {'drive': .text('b!xyz'), 'folder': .text('01abc')},
    action: .of(action),
    arguments:
        arguments ??
        [
          const BoundReference('drive'),
          const BoundReference('folder'),
          const InputReference('name'),
          const InputReference('offset'),
          const InputReference('mode'),
          Literal.integer(5000),
          Literal.text(r'$budget.docx'),
          Literal.boolean(true),
        ],
  );
  const call = <String, Object?>{
    'name': 'a.docx',
    'tags': ['x'],
    'weight': 0.5,
    'at': {'line': 1},
  };

  test('the wire shape is one object, steps a single propose', () {
    expect(
      jsonEncode(readDocument().toJson()),
      '{"name":"read_document","description":"Reads a Word document.",'
      '"input_schema":${jsonEncode(input.schema)},'
      '"bound":{"drive":"b!xyz","folder":"01abc"},'
      '"steps":["propose","readDocument",["bound","drive"],["bound","folder"],'
      r'["input","name"],["input","offset"],["input","mode"],5000,"$budget.docx",true]}',
    );
  });

  test('a tool read back from the wire writes the same JSON', () {
    final wire = readDocument().toJson();
    expect(
      jsonEncode(OneActionTool.parse(sent(wire))!.toJson()),
      jsonEncode(wire),
    );
  });

  test('a call fills in bound values, input fields and defaults', () {
    final tool = OneActionTool.parse(sent(readDocument().toJson()))!;
    expect(tool.argumentsFor(const .of(call)), [
      'b!xyz',
      '01abc',
      'a.docx',
      0,
      'list',
      5000,
      r'$budget.docx',
      true,
    ]);
  });

  group('a call is refused, naming the field', () {
    final cases = <String, (Map<String, Object?>, String, String)>{
      'one the input refuses': (
        {...call, 'name': ''},
        'name',
        'a string of at least 1 character',
      ),
      'a string over 64 KiB': (
        {...call, 'name': 'x' * (64 * 1024 + 1)},
        'name',
        'a string of at most 64 KiB in UTF-8',
      ),
      'a number past 2^53': (
        {...call, 'offset': 9007199254740992},
        'offset',
        'a whole number within ±2^53',
      ),
    };
    for (final MapEntry(key: label, value: (json, field, wanted))
        in cases.entries) {
      test(label, () {
        expect(
          () => readDocument().argumentsFor(.of(json)),
          throwsA(
            isA<JsonFieldException>()
                .having((e) => e.field, 'field', field)
                .having((e) => e.wanted, 'wanted', wanted),
          ),
        );
      });
    }
  });

  group('a tool made in Dart with a bad reference throws', () {
    final cases = <String, OneActionTool Function()>{
      'an optional field': () =>
          readDocument(arguments: [const InputReference('note')]),
      'a list field': () =>
          readDocument(arguments: [const InputReference('tags')]),
      'a number field': () =>
          readDocument(arguments: [const InputReference('weight')]),
      'an object field': () =>
          readDocument(arguments: [const InputReference('at')]),
      'an action name with a space': () =>
          readDocument(action: 'read document'),
      'a field the input lacks': () =>
          readDocument(arguments: [const InputReference('size')]),
      'a bound value not set': () =>
          readDocument(arguments: [const BoundReference('site')]),
      'an empty name': () => readDocument(name: ''),
      'an empty action': () => readDocument(action: ''),
    };
    for (final MapEntry(key: label, value: make) in cases.entries) {
      test(label, () => expect(make, throwsArgumentError));
    }
  });

  group('JSON a tool never writes is not read', () {
    final good = readDocument().toJson().asUncheckedMap();
    Map<String, Object?> withSteps(List<Object?> args) => {
      ...good,
      'steps': ['propose', 'readDocument', ...args],
    };
    final refused = <String, Map<String, Object?>>{
      'no bound': {...good}..remove('bound'),
      'an output schema': {...good, 'output_schema': <String, Object?>{}},
      'a concurrent flag': {...good, 'concurrent': true},
      'a name that is not a string': {...good, 'name': 3},
      'an input schema an Input never writes': {
        ...good,
        'input_schema': {'type': 'object'},
      },
      'a bound value that is a list': {
        ...good,
        'bound': {
          'drive': ['b!xyz'],
        },
      },
      'steps that are not a propose': {
        ...good,
        'steps': [
          'fail',
          ['input', 'name'],
        ],
      },
      'an action that is not a string': {
        ...good,
        'steps': ['propose', 3],
      },
      'no action': {
        ...good,
        'steps': ['propose'],
      },
      'a nested form': withSteps([
        [
          'concat',
          ['input', 'name'],
          '.docx',
        ],
      ]),
      'a reference with no name': withSteps([
        ['input'],
      ]),
      'a reference to an optional field': withSteps([
        ['input', 'note'],
      ]),
      'a reference to a list field': withSteps([
        ['input', 'tags'],
      ]),
      'a reference to a number field': withSteps([
        ['input', 'weight'],
      ]),
      'a reference to an object field': withSteps([
        ['input', 'at'],
      ]),
      'an action name with a space': {
        ...good,
        'steps': ['propose', 'read document'],
      },
      'an empty action name': {
        ...good,
        'steps': ['propose', ''],
      },
      'a reference to an unbound value': withSteps([
        ['bound', 'site'],
      ]),
      'a null literal': withSteps([null]),
      'a fractional literal': withSteps([1.5]),
      'an object literal': withSteps([<String, Object?>{}]),
      'an integer past 2^53': withSteps([9007199254740992]),
      'a string over 64 KiB': withSteps(['x' * (64 * 1024 + 1)]),
    };
    test('the tool itself is read', () {
      expect(OneActionTool.parse(sent(.of(good))), isNotNull);
    });
    for (final MapEntry(key: label, value: json) in refused.entries) {
      test(label, () => expect(OneActionTool.parse(sent(.of(json))), isNull));
    }
  });

  test('a literal outside its bounds is refused when made', () {
    expect(() => Literal.integer(9007199254740992), throwsArgumentError);
    expect(() => Literal.text('x' * (64 * 1024 + 1)), throwsArgumentError);
    expect(Literal.integer(-9007199254740991).json, -9007199254740991);
  });

  test('the fields every read gives a string, whole number or boolean', () {
    expect(input.namesAlwaysReadAsStringIntegerOrBoolean, {
      'name',
      'offset',
      'mode',
    });
  });

  test('an action name is letters, digits, _ and -', () {
    expect(ActionName.parse('make-web-requests')?.text, 'make-web-requests');
    expect(
      ActionName.parse('docx_to_Passage2'),
      ActionName.of('docx_to_Passage2'),
    );
    for (final bad in ['', 'a b', 'a/b', 'a.b', ' a']) {
      expect(ActionName.parse(bad), isNull, reason: bad);
    }
  });
}
