import 'package:test/test.dart';
import 'package:is_tool_definition_vocabulary/is_tool_definition_vocabulary.dart';

void main() {
  final input = Input.fields3(
    Field('name', .string()),
    Field('count', .integer(minimum: 0)),
    Field('dry', .boolean()),
    (a, b, c) => (a, b, c),
  );

  test('each field is read at its own type', () {
    expect(input.read(.of({'name': 'x', 'count': 2, 'dry': true})), (
      'x',
      2,
      true,
    ));
  });

  test('of two bad fields, the one listed first is reported', () {
    // `dry` comes first in the object; `count` comes first in the Input.
    expect(
      () => input.read(.of({'dry': 'yes', 'name': 'x', 'count': -1})),
      throwsA(
        isA<JsonFieldException>().having((e) => e.field, 'field', 'count'),
      ),
    );
  });
}
