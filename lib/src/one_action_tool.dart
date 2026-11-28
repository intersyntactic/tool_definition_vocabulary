import 'package:checked_json/checked_json.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart';

import 'input.dart';
import 'expression.dart';

/// A tool sent as data whose steps propose one action: the airlock
/// [program] to run, and the [programInput] expression that builds its
/// input from each call.
///
/// On the wire it is one JSON object, `name`, `description`,
/// `input_schema` and `steps`, where `steps` is
/// `["propose", <program>, <expression>]`. The program is named as the
/// airlock names it, and the expression builds the program's input as the
/// airlock writes that program's input in a proposal. So this package
/// knows no program: the airlock reads the filled input with the program's
/// own reader, and refuses it there.
///
/// The model's input reaches the action only through the expression's
/// `["input", <field>]` references, and each one names a field every read
/// of [input] gives a value for, so no call leaves one unfilled.
///
/// A tool written before steps held an expression,
/// `["propose", "fetch", <origin>, <path>, <sign-in>]`, is read as the fetch
/// it always was, keeping the response as text. It is written back exactly
/// as it was read.
final class OneActionTool {
  OneActionTool._(
    this.name,
    this.description,
    this.input,
    this.program,
    this.programInput,
    this._steps,
  );

  final ToolName name;
  final String description;

  /// What a call takes, read back from its schema, so the schema the model
  /// is shown and the checker of what it sent are one description.
  final Input<JsonObject> input;

  /// The airlock program a call proposes.
  final AirlockProgramName program;

  /// What builds the program's input from a call.
  final Expression programInput;

  /// `steps` as this tool was read or made.
  final Object? _steps;

  /// The tool made in Dart, from the [input] its module built. An
  /// [ArgumentError] when [programInput] reads a field that some read of
  /// [input] gives no value for.
  factory OneActionTool.of({
    required ToolName name,
    required String description,
    required Input<Object?> input,
    required AirlockProgramName program,
    required Expression programInput,
  }) {
    // An Input's own schema is always one Input.parse reads.
    final read = Input.parse(input.schema)!;
    if (_unfilled(programInput, read) case final field?) {
      throw ArgumentError.value(
        field,
        'programInput',
        'reads a field that is neither required nor given a default',
      );
    }
    return OneActionTool._(name, description, read, program, programInput, [
      _propose,
      program.value,
      programInput.toJson(),
    ]);
  }

  /// What the model is shown of this tool.
  OfferedTool get offered => OfferedTool(
    name: name,
    description: description,
    inputSchema: input.schema,
  );

  /// What [call] proposes: [program], and its input with every reference
  /// filled from [call] as [input] reads it. A [JsonFieldException] naming
  /// the field when [input] refuses [call].
  ({AirlockProgramName program, Object? input}) proposedFor(JsonObject call) =>
      (program: program, input: programInput.filledFrom(input.read(call)));

  /// The tool [json] describes, as [toJson] writes it; null for any other
  /// object.
  static OneActionTool? parse(JsonObject json) {
    if (!json.keys.every(_keys.contains) || json.keys.length != _keys.length) {
      return null;
    }
    final steps = json.raw('steps');
    final parsed = switch ((
      _toolName(json.raw('name')),
      json.raw('description'),
      JsonObject.parse(json.raw('input_schema')),
      _proposal(steps),
    )) {
      (
        final name?,
        final String description,
        final schema?,
        (final program, final programInput)?,
      ) =>
        switch (Input.parse(schema)) {
          final input? => OneActionTool._(
            name,
            description,
            input,
            program,
            programInput,
            steps,
          ),
          null => null,
        },
      _ => null,
    };
    return parsed == null ||
            _unfilled(parsed.programInput, parsed.input) != null
        ? null
        : parsed;
  }

  static const _keys = {'name', 'description', 'input_schema', 'steps'};

  JsonObject toJson() => .of({
    'name': name.value,
    'description': description,
    'input_schema': input.schema,
    'steps': _steps,
  });
}

/// The program and expression [steps] propose, in either spelling; null for
/// anything else.
(AirlockProgramName, Expression)? _proposal(Object? steps) => switch (steps) {
  [_propose, final String program, final expression] => switch ((
    AirlockProgramName.parse(program),
    Expression.parse(expression),
  )) {
    (final program?, final expression?) => (program, expression),
    _ => null,
  },
  [
    _propose,
    _fetch,
    final String origin,
    final String path,
    final String signIn,
  ] =>
    switch (Expression.quoting({
      'origin': origin,
      'path': path,
      'signIn': signIn,
      'keep': 'text',
    })) {
      final expression? => (const AirlockProgramName._(_fetch), expression),
      null => null,
    },
  _ => null,
};

/// The first field [expression] reads that some read of [input] gives no value
/// for; null when there is none.
String? _unfilled(Expression expression, Input<Object?> input) => expression
    .inputFields
    .where((f) => !input.namesAlwaysRead.contains(f))
    .firstOrNull;

/// The tool name [json] is, or null if it is none.
ToolName? _toolName(Object? json) =>
    json is String ? ToolName.parse(json) : null;

/// A program's name as the airlock writes it in a proposal, such as `fetch`
/// or `read-bytes`: lower-case words joined by hyphens.
///
/// Which names are programs is the airlock's to say; a name no program has
/// is refused when the airlock reads the proposal.
final class AirlockProgramName {
  const AirlockProgramName._(this.value);

  final String value;

  /// [raw] as a program name; null unless it is lower-case letters and
  /// digits in hyphen-joined words, starting with a letter, at most 64
  /// characters.
  static AirlockProgramName? parse(String raw) =>
      raw.length <= 64 && _shape.hasMatch(raw)
      ? AirlockProgramName._(raw)
      : null;

  static final _shape = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');

  @override
  bool operator ==(Object other) =>
      other is AirlockProgramName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The form `steps` is written in.
const _propose = 'propose';

/// The one program the spelling before expressions could propose.
const _fetch = 'fetch';
