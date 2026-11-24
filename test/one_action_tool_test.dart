import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tools_api/is_tools_api.dart';

/// [json] as it arrives over the wire.
JsonObject sent(JsonObject json) => .decode(jsonEncode(json));

void main() {
  final listing = Fetch(
    Origin.parse('https://graph.microsoft.com')!,
    WebPath.parse('/v1.0/drives/b!xyz/items/01abc/children')!,
    SignIn.parse('cam-bot')!,
  );
  OneActionTool listCaseFolder({ToolAction? action}) => .of(
    name: ToolName.of('list'),
    description: 'Lists the case folder.',
    input: Input.none,
    action: action ?? listing,
  );

  test('the wire shape is one object, steps a single propose of a fetch', () {
    expect(
      jsonEncode(listCaseFolder().toJson()),
      '{"name":"list","description":"Lists the case folder.",'
      '"input_schema":{"type":"object","properties":{},"required":[],'
      '"additionalProperties":false},'
      '"steps":["propose","fetch","https://graph.microsoft.com",'
      '"/v1.0/drives/b!xyz/items/01abc/children","cam-bot"]}',
    );
  });

  test('a tool read back from the wire writes the same JSON', () {
    for (final tool in [
      listCaseFolder(),
      listCaseFolder(
        action: Fetch(listing.origin, WebPath.root, listing.signIn),
      ),
    ]) {
      final wire = tool.toJson();
      final read = OneActionTool.parse(sent(wire));
      expect(read, isNotNull);
      expect(jsonEncode(read!.toJson()), jsonEncode(wire));
    }
  });

  test('the action read back is the fetch that was written', () {
    final action = OneActionTool.parse(sent(listCaseFolder().toJson()))!.action;
    expect(action, isA<Fetch>());
    final Fetch(:origin, :path, :signIn) = action as Fetch;
    expect(
      (origin, path, signIn),
      (listing.origin, listing.path, listing.signIn),
    );
  });

  test('what the model is offered is the name, description and schema', () {
    final tool = listCaseFolder();
    final OfferedTool(:name, :description, :inputSchema) = tool.offered;
    expect(name, tool.name);
    expect(description, tool.description);
    expect(jsonEncode(inputSchema), jsonEncode(tool.input.schema));
  });

  group('JSON a tool never writes is not read', () {
    final good = listCaseFolder().toJson().asUncheckedMap();
    final steps = [
      'propose',
      'fetch',
      'https://graph.microsoft.com',
      '/v1.0/x',
      'cam-bot',
    ];
    Map<String, Object?> withSteps(List<Object?> s) => {...good, 'steps': s};
    List<Object?> replacing(int i, Object? value) => [...steps]..[i] = value;
    final refused = <String, Map<String, Object?>>{
      'bound, which stage 1 dropped': {...good, 'bound': <String, Object?>{}},
      'an output schema': {...good, 'output_schema': <String, Object?>{}},
      'a concurrent flag': {...good, 'concurrent': true},
      'no steps': {...good}..remove('steps'),
      'an empty name': {...good, 'name': ''},
      'a name with a dot': {...good, 'name': 'web.fetch'},
      'a name of 65 characters': {...good, 'name': 'a' * 65},
      'a name that is not a string': {...good, 'name': 3},
      'an input schema an Input never writes': {
        ...good,
        'input_schema': {'type': 'object'},
      },
      'steps that are not a propose': withSteps(replacing(0, 'fail')),
      'an action kind stage 1 lacks': withSteps(replacing(1, 'read')),
      'a fetch with no sign-in': withSteps(steps.sublist(0, 4)),
      'a fetch with an extra argument': withSteps([...steps, 'x']),
      'an origin with a path': withSteps(
        replacing(2, 'https://graph.microsoft.com/v1.0'),
      ),
      'an origin that is not http': withSteps(replacing(2, 'ftp://a.example')),
      'a path that climbs': withSteps(replacing(3, '/v1.0/../admin')),
      'a path with no leading slash': withSteps(replacing(3, 'v1.0/x')),
      'a sign-in with capitals': withSteps(replacing(4, 'Cam-Bot')),
      'a sign-in that is not a string': withSteps(replacing(4, 3)),
      'a reference where a value goes': withSteps(
        replacing(3, ['input', 'path']),
      ),
    };
    test('the steps used here are read', () {
      expect(OneActionTool.parse(sent(.of(withSteps(steps)))), isNotNull);
    });
    for (final MapEntry(key: label, value: json) in refused.entries) {
      test(label, () => expect(OneActionTool.parse(sent(.of(json))), isNull));
    }
  });
}
