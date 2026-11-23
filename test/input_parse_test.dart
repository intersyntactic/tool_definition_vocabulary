import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tools_api/is_tools_api.dart';

enum Mode { list, stage }

/// What reading [json] with [input] comes to: `ok`, or the field it refused
/// and what that field should have been.
Object? outcome<I>(Input<I> input, JsonObject json) {
  try {
    input.read(json);
    return 'ok';
  } on JsonFieldException catch (e) {
    return (e.field, e.wanted);
  }
}

/// [schema] as it arrives over the wire.
JsonObject sent(JsonObject schema) => .decode(jsonEncode(schema));

void main() {
  // Every kind of Schema and Field this library makes, nested where it nests.
  final everything = Input.fields8(
    Field('name', .string(minLength: 1, maxLength: 4), description: 'A name.'),
    Field.orDefault('context', .integer(minimum: 0, maximum: 3), 3),
    Field.optional('weight', .number(minimum: 0.5)),
    Field.optional('dry', .boolean()),
    Field('mode', .choice(Mode.values)),
    Field('hunks', .list(.integer(minimum: 1), minItems: 1, maxItems: 2)),
    Field(
      'at',
      .object(
        .fields2(
          Field('line', .integer()),
          Field.optional('tags', .list(.string(maxLength: 2))),
          (a, b) => (a, b),
        ),
      ),
    ),
    Field.orDefault('modes', .list(.choice(Mode.values)), const [Mode.stage]),
    (a, b, c, d, e, f, g, h) => (a, b, c, d, e, f, g, h),
  );
  final listOfObjects = Input.field(
    Field.optional(
      'rows',
      .list(.object(.field(Field('id', .string()))), maxItems: 2),
    ),
  );

  const good = <String, Object?>{
    'name': 'ab',
    'mode': 'list',
    'hunks': [1],
    'at': {'line': 3},
  };
  final everythingCases = <Map<String, Object?>>[
    good,
    {...good, 'context': 0, 'weight': 0.5, 'dry': false, 'modes': <Object?>[]},
    {...good, 'context': 2.0, 'weight': 7},
    {
      ...good,
      'at': {
        'line': 1,
        'tags': ['ab', 'c'],
      },
    },
    {...good, 'name': ''},
    {...good, 'name': 'abcde'},
    {...good, 'name': 'abcd'},
    {...good, 'name': 3},
    {...good, 'context': 4},
    {...good, 'context': -1},
    {...good, 'context': 1.5},
    {...good, 'weight': 0.4},
    {...good, 'weight': 'x'},
    {...good, 'dry': 'yes'},
    {...good, 'mode': 'other'},
    {...good, 'mode': null},
    {...good, 'hunks': <Object?>[]},
    {
      ...good,
      'hunks': [1, 2, 3],
    },
    {
      ...good,
      'hunks': [1, 0],
    },
    {...good, 'hunks': 'x'},
    {...good, 'at': 'x'},
    {...good, 'at': <String, Object?>{}},
    {
      ...good,
      'at': {'line': 1, 'col': 2},
    },
    {
      ...good,
      'at': {
        'line': 1,
        'tags': ['abc'],
      },
    },
    {
      ...good,
      'modes': ['list', 'x'],
    },
    {...good, 'extra': 1},
    {'mode': 'x', 'name': ''},
    {'dry': 'x', 'context': 9, 'name': ''},
    <String, Object?>{},
  ];
  final listOfObjectsCases = <Map<String, Object?>>[
    {},
    {'rows': <Object?>[]},
    {
      'rows': [
        {'id': 'a'},
        {'id': 'b'},
      ],
    },
    {
      'rows': [
        {'id': 'a'},
        {'id': 3},
      ],
    },
    {
      'rows': [
        {'id': 'a'},
        {'id': 'b'},
        {'id': 'c'},
      ],
    },
    {
      'rows': [
        {'id': 'a', 'x': 1},
      ],
    },
  ];

  group('a parsed schema reads as the Input that wrote it', () {
    for (final (label, input, cases) in [
      ('every kind of field', everything, everythingCases),
      ('a list of objects', listOfObjects, listOfObjectsCases),
      (
        'no fields',
        Input.none,
        [
          <String, Object?>{},
          {'x': 1},
        ],
      ),
    ]) {
      test(label, () {
        final parsed = Input.parse(sent(input.schema));
        expect(parsed, isNotNull);
        expect(jsonEncode(parsed!.schema), jsonEncode(input.schema));
        for (final c in cases) {
          final json = JsonObject.of(c);
          expect(outcome(parsed, json), outcome(input, json), reason: '$c');
        }
      });
    }
  });

  test('a parsed input is read as JSON, defaults in, absent optionals out', () {
    final parsed = Input.parse(sent(everything.schema))!;
    expect(parsed.read(.of({...good, 'context': 2.0, 'dry': null})), {
      'name': 'ab',
      'context': 2,
      'mode': 'list',
      'hunks': [1],
      'at': {'line': 3},
      'modes': ['stage'],
    });
  });

  group('a schema an Input never writes is not read', () {
    final base = {
      'type': 'object',
      'properties': {
        'n': {'type': 'integer', 'minimum': 1, 'default': 2},
      },
      'required': <Object?>[],
      'additionalProperties': false,
    };
    Map<String, Object?> withN(Map<String, Object?> n) => {
      ...base,
      'properties': {'n': n},
    };
    final refused = <String, Map<String, Object?>>{
      'additional properties allowed': {...base, 'additionalProperties': true},
      'no additionalProperties': {...base}..remove('additionalProperties'),
      'no required': {...base}..remove('required'),
      'an unknown top-level key': {...base, r'$schema': 'x'},
      'not an object': {...base, 'type': 'array'},
      'a required name with no property': {
        ...base,
        'required': ['m'],
      },
      'a name required twice': withN({'type': 'string'})
        ..['required'] = ['n', 'n'],
      'required with a default': {
        ...base,
        'required': ['n'],
      },
      'a default outside the schema': withN({
        'type': 'integer',
        'minimum': 1,
        'default': 0,
      }),
      'a default on an object': withN({
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <Object?>[],
        'additionalProperties': false,
        'default': <String, Object?>{},
      }),
      'a default on a list of objects': withN({
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': <Object?>[],
          'additionalProperties': false,
        },
        'default': <Object?>[],
      }),
      'a null default': withN({'type': 'string', 'default': null}),
      'a description that is not a string': withN({
        'type': 'string',
        'description': 3,
      }),
      'a description on list items': withN({
        'type': 'array',
        'items': {'type': 'string', 'description': 'x'},
      }),
      'a fractional integer bound': withN({'type': 'integer', 'minimum': 1.5}),
      'a string bound': withN({'type': 'string', 'maxLength': '3'}),
      'a constraint of another type': withN({'type': 'string', 'minimum': 1}),
      'a length bound on a choice': withN({
        'type': 'string',
        'enum': ['a'],
        'minLength': 1,
      }),
      'a choice that is not strings': withN({
        'type': 'string',
        'enum': [1],
      }),
      'a pattern': withN({'type': 'string', 'pattern': 'x'}),
      'a union type': withN({
        'type': ['string', 'null'],
      }),
      'no type': withN({
        'enum': ['a'],
      }),
      'a null type': withN({'type': 'null'}),
      'a list with no items': withN({'type': 'array'}),
      'a nested object that allows more': withN({
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <Object?>[],
        'additionalProperties': true,
      }),
    };
    test('the base case is read', () {
      expect(Input.parse(.of(base)), isNotNull);
    });
    for (final MapEntry(key: label, value: schema) in refused.entries) {
      test(label, () => expect(Input.parse(sent(.of(schema))), isNull));
    }
  });

  test(
    'a default its own schema refuses is refused when the field is made',
    () {
      expect(
        () => Field.orDefault('n', .integer(minimum: 1), 0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'is not an integer from 1',
          ),
        ),
      );
    },
  );
}
