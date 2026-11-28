import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tool_definition_vocabulary/is_tool_definition_vocabulary.dart';

/// [json] as it arrives over the wire.
JsonObject sent(Object? json) => .decode(jsonEncode(json));

void main() {
  final fetch = AirlockProgramName.parse('fetch')!;
  final listing = Expression.record({
    'origin': Expression.text('https://graph.microsoft.com'),
    'path': Expression.text('/v1.0/drives/b!xyz/items/01abc/children'),
    'signIn': Expression.text('cam-bot'),
    'keep': Expression.text('text'),
  });
  OneActionTool listCaseFolder() => .of(
    name: ToolName.of('list'),
    description: 'Lists the case folder.',
    input: Input.none,
    program: fetch,
    programInput: listing,
  );

  final readPart = Input.fields2(
    Field('document', Schema.string()),
    Field('handle', Schema.string()),
    (document, handle) => (document, handle),
  );
  OneActionTool readDocumentPart() => .of(
    name: ToolName.of('read_document_part'),
    description: 'Reads one part of a fetched Word document.',
    input: readPart,
    program: AirlockProgramName.parse('read-document-part')!,
    programInput: Expression.record({
      'document': Expression.input('document'),
      'part': Expression.input('handle'),
    }),
  );

  const schemaNone =
      '{"type":"object","properties":{},"required":[],'
      '"additionalProperties":false}';

  group('a tool stored before steps held an expression', () {
    // Today's spelling, as TrajectoryStarted keeps it in the logbook, where
    // a restarted agent loop reads it back.
    const stored =
        '{"name":"list","description":"Lists the case folder.",'
        '"input_schema":$schemaNone,'
        '"steps":["propose","fetch","https://graph.microsoft.com",'
        '"/v1.0/drives/b!xyz/items/01abc/children","cam-bot"]}';

    test('is read as a fetch that keeps the response as text', () {
      final tool = OneActionTool.parse(.decode(stored))!;
      final (:program, :input) = tool.proposedFor(.of({}));
      expect(program, fetch);
      expect(
        jsonEncode(input),
        '{"origin":"https://graph.microsoft.com",'
        '"path":"/v1.0/drives/b!xyz/items/01abc/children",'
        '"signIn":"cam-bot","keep":"text"}',
      );
    });

    test('is written back exactly as it was stored', () {
      expect(
        jsonEncode(OneActionTool.parse(.decode(stored))!.toJson()),
        stored,
      );
    });
  });

  test('steps are one propose of a program and its input expression', () {
    expect(
      jsonEncode(listCaseFolder().toJson()),
      '{"name":"list","description":"Lists the case folder.",'
      '"input_schema":$schemaNone,'
      '"steps":["propose","fetch",["record",'
      '"origin","https://graph.microsoft.com",'
      '"path","/v1.0/drives/b!xyz/items/01abc/children",'
      '"signIn","cam-bot","keep","text"]]}',
    );
  });

  test('a tool read back from the wire writes the same JSON', () {
    for (final tool in [listCaseFolder(), readDocumentPart()]) {
      final wire = tool.toJson();
      final read = OneActionTool.parse(sent(wire));
      expect(read, isNotNull);
      expect(jsonEncode(read!.toJson()), jsonEncode(wire));
    }
  });

  group('a call', () {
    final tool = OneActionTool.parse(sent(readDocumentPart().toJson()))!;

    test('fills each reference from the call', () {
      final (:program, :input) = tool.proposedFor(
        sent({'document': 'toolu_01', 'handle': 'c3'}),
      );
      expect(program.value, 'read-document-part');
      expect(jsonEncode(input), '{"document":"toolu_01","part":"c3"}');
    });

    test('the input refuses is refused, naming the field', () {
      expect(
        () => tool.proposedFor(sent({'document': 'toolu_01'})),
        throwsA(
          isA<JsonFieldException>().having((e) => e.field, 'field', 'handle'),
        ),
      );
      expect(
        () => tool.proposedFor(sent({'document': 'toolu_01', 'handle': 3})),
        throwsA(isA<JsonFieldException>()),
      );
    });

    test('a field with a default fills with the default', () {
      final withDefault = OneActionTool.of(
        name: ToolName.of('t'),
        description: 'd',
        input: Input.field(Field.orDefault<int>('n', Schema.integer(), 5)),
        program: fetch,
        programInput: Expression.list([
          Expression.input('n'),
          Expression.boolean(true),
        ]),
      );
      expect(jsonEncode(withDefault.proposedFor(.of({})).input), '[5,true]');
    });
  });

  test('a reference to an optional field is refused in Dart', () {
    expect(
      () => OneActionTool.of(
        name: ToolName.of('t'),
        description: 'd',
        input: Input.field(Field.optional('n', Schema.string())),
        program: fetch,
        programInput: Expression.input('n'),
      ),
      throwsArgumentError,
    );
  });

  test('a whole number past 2^53 - 1 is no expression', () {
    expect(Expression.parse(9007199254740991), isNotNull);
    expect(Expression.parse(9007199254740992), isNull);
    expect(Expression.parse(-9007199254740992), isNull);
  });

  test('what the model is offered is the name, description and schema', () {
    final tool = listCaseFolder();
    final OfferedTool(:name, :description, :inputSchema) = tool.offered;
    expect(name, tool.name);
    expect(description, tool.description);
    expect(jsonEncode(inputSchema), jsonEncode(tool.input.schema));
  });

  group('JSON a tool never writes is not read', () {
    final good = readDocumentPart().toJson().asUncheckedMap();
    Map<String, Object?> withSteps(List<Object?> s) => {...good, 'steps': s};
    List<Object?> proposing(Object? expression) => [
      'propose',
      'fetch',
      expression,
    ];
    Object? nested(int depth) => depth == 0 ? 'x' : ['list', nested(depth - 1)];
    final refused = <String, Map<String, Object?>>{
      'bound, which stage 1 dropped': {...good, 'bound': <String, Object?>{}},
      'an output schema': {...good, 'output_schema': <String, Object?>{}},
      'no steps': {...good}..remove('steps'),
      'an empty name': {...good, 'name': ''},
      'a name with a dot': {...good, 'name': 'web.fetch'},
      'an input schema an Input never writes': {
        ...good,
        'input_schema': {'type': 'object'},
      },
      'steps that are not a propose': withSteps(['fail', 'fetch', 'x']),
      'a program name with capitals': withSteps(['propose', 'Fetch', 'x']),
      'a program name with a space': withSteps(['propose', 'read file', 'x']),
      'a propose of two expressions': withSteps(['propose', 'fetch', 'x', 'y']),
      'a reference to a field the input lacks': withSteps(
        proposing(['input', 'path']),
      ),
      'an empty reference': withSteps(proposing(['input', ''])),
      'an array that is no form': withSteps(proposing(['a', 'b'])),
      'an object, which is written as a record': withSteps(
        proposing({'a': 'b'}),
      ),
      'a null': withSteps(proposing(null)),
      'a fraction': withSteps(proposing(1.5)),
      'a record with a key and no expression': withSteps(
        proposing(['record', 'a']),
      ),
      'a record with a key written twice': withSteps(
        proposing(['record', 'a', 'x', 'a', 'y']),
      ),
      'a record with an empty key': withSteps(proposing(['record', '', 'x'])),
      'a record with a key that is not a string': withSteps(
        proposing(['record', 1, 'x']),
      ),
      'an expression nested past 64': withSteps(proposing(nested(65))),
      'a stored fetch with no sign-in': withSteps([
        'propose',
        'fetch',
        'https://graph.microsoft.com',
        '/v1.0/x',
      ]),
    };
    test('an expression nested 64 deep is read', () {
      expect(
        OneActionTool.parse(sent(withSteps(proposing(nested(64))))),
        isNotNull,
      );
    });
    for (final MapEntry(key: label, value: json) in refused.entries) {
      test(label, () => expect(OneActionTool.parse(sent(json)), isNull));
    }
  });
}
