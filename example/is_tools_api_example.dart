import 'dart:convert';

import 'package:is_tools_api/is_tools_api.dart';

final echo = ToolSpec<String, String>(
  name: 'echo',
  description: 'Say the text back.',
  input: .field(Field('text', .string(), description: 'What to say back.')),
  output: .text,
);

void main() {
  // What the model is sent, and what it costs in a request.
  print(jsonEncode(echo.toJson()));
  print('${echo.wireBytes} bytes');

  // What the model sent, read as the String the tool takes.
  print(echo.input.read(JsonObject.decode('{"text": "hello"}')));
}
