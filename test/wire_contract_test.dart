import 'dart:convert';

import 'package:test/test.dart';
import 'package:is_tool_definition_vocabulary/is_tool_definition_vocabulary.dart';

enum Mode { list, stage }

void main() {
  test('tool definition wire shape excludes execution metadata', () {
    final spec = ToolSpec<String, String>(
      name: ToolName.of('file_read'),
      description: 'Read a file.',
      input: .field(
        Field('path', .string(minLength: 1), description: 'From the root.'),
      ),
      output: .text,
      concurrent: true,
    );
    const wire =
        '{"name":"file_read","description":"Read a file.",'
        '"input_schema":{"type":"object","properties":'
        '{"path":{"type":"string","minLength":1,"description":"From the root."}},'
        '"required":["path"],"additionalProperties":false}}';
    expect(jsonEncode(spec.toJson()), wire);
    expect(spec.wireBytes, utf8.encode(wire).length);

    final OfferedTool(:name, :description, :inputSchema) = spec.offered;
    expect(name, spec.name);
    expect(description, spec.description);
    expect(jsonEncode(inputSchema), jsonEncode(spec.inputSchema));
  });

  test('each kind of field is shown to the model as JSON Schema', () {
    final input = Input.fields8(
      Field('name', .string(maxLength: 40)),
      Field.orDefault('context', .integer(minimum: 0, maximum: 3), 3),
      Field.optional('weight', .number(minimum: 0)),
      Field.optional('dry', .boolean()),
      Field('mode', .choice(Mode.values)),
      Field('hunks', .list(.integer(minimum: 1), minItems: 1)),
      Field('at', .object(.field(Field('line', .integer())))),
      Field.orDefault('tags', .list(.string()), const ['a']),
      (a, b, c, d, e, f, g, h) => (a, b, c, d, e, f, g, h),
    );
    expect(
      jsonEncode(input.schema),
      '{"type":"object","properties":{'
      '"name":{"type":"string","maxLength":40},'
      '"context":{"type":"integer","minimum":0,"maximum":3,"default":3},'
      '"weight":{"type":"number","minimum":0},'
      '"dry":{"type":"boolean"},'
      '"mode":{"type":"string","enum":["list","stage"]},'
      '"hunks":{"type":"array","items":{"type":"integer","minimum":1},'
      '"minItems":1},'
      '"at":{"type":"object","properties":{"line":{"type":"integer"}},'
      '"required":["line"],"additionalProperties":false},'
      '"tags":{"type":"array","items":{"type":"string"},"default":["a"]}},'
      '"required":["name","mode","hunks","at"],"additionalProperties":false}',
    );
  });
}
