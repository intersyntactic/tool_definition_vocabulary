import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tools_api/is_tools_api.dart';

/// [json] as it arrives over the wire.
JsonObject sent(JsonObject json) => .decode(jsonEncode(json));

void main() {
  final input = Input.fields4(
    Field('name', .string(minLength: 1), description: 'The file name.'),
    Field.orDefault('offset', .integer(minimum: 0), 0),
    Field.optional('note', .string()),
    Field('tags', .list(.string())),
    (a, b, c, d) => (a, b, c, d),
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
    action: action,
    arguments:
        arguments ??
        [
          const BoundReference('drive'),
          const BoundReference('folder'),
          const InputReference('name'),
          const InputReference('offset'),
          const InputReference('tags'),
          Literal.integer(5000),
          Literal.text(r'$budget.docx'),
          Literal.boolean(true),
        ],
  );

  test('the wire shape is one object, steps a single propose', () {
    expect(
      jsonEncode(readDocument().toJson()),
      '{"name":"read_document","description":"Reads a Word document.",'
      '"input_schema":${jsonEncode(input.schema)},'
      '"bound":{"drive":"b!xyz","folder":"01abc"},'
      '"steps":["propose","readDocument",["bound","drive"],["bound","folder"],'
      r'["input","name"],["input","offset"],["input","tags"],5000,"$budget.docx",true]}',
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
    expect(
      tool.argumentsFor(
        .of({
          'name': 'a.docx',
          'tags': ['x'],
        }),
      ),
      [
        'b!xyz',
        '01abc',
        'a.docx',
        0,
        ['x'],
        5000,
        r'$budget.docx',
        true,
      ],
    );
  });

  test('a call the input refuses is refused as the input refuses it', () {
    expect(
      () => readDocument().argumentsFor(.of({'name': '', 'tags': <Object?>[]})),
      throwsA(
        isA<JsonFieldException>().having((e) => e.field, 'field', 'name'),
      ),
    );
  });

  group('a tool made in Dart with a bad reference throws', () {
    final cases = <String, OneActionTool Function()>{
      'an optional field': () =>
          readDocument(arguments: [const InputReference('note')]),
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

  test('the fields every read gives a value for', () {
    expect(input.namesAlwaysRead, {'name', 'offset', 'tags'});
  });
}
