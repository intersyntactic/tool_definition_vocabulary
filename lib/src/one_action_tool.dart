import 'package:checked_json/checked_json.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart';
import 'package:is_sign_in_vocabulary/is_sign_in_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart';

import 'input.dart';

/// A tool sent as data whose steps are one proposed [action]: its name,
/// description and [input], and the action, fixed when the tool was made.
///
/// On the wire it is one JSON object, `name`, `description`,
/// `input_schema` and `steps`, where `steps` is `["propose", <action>…]`
/// as [ToolAction] spells it. Every value in `steps` is literal text: the
/// model's input reaches nothing in the action.
final class OneActionTool {
  OneActionTool._(this.name, this.description, this.input, this.action);

  final ToolName name;
  final String description;

  /// What a call takes, read back from its schema, so the schema the model
  /// is shown and the checker of what it sent are one description.
  final Input<JsonObject> input;

  /// What a call to this tool proposes.
  final ToolAction action;

  /// The tool made in Dart, from the [input] its module built.
  factory OneActionTool.of({
    required ToolName name,
    required String description,
    required Input<Object?> input,
    required ToolAction action,
  }) =>
      // An Input's own schema is always one Input.parse reads.
      OneActionTool._(name, description, Input.parse(input.schema)!, action);

  /// What the model is shown of this tool.
  OfferedTool get offered => OfferedTool(
    name: name,
    description: description,
    inputSchema: input.schema,
  );

  /// The tool [json] describes, as [toJson] writes it; null for any other
  /// object.
  static OneActionTool? parse(JsonObject json) {
    if (!json.keys.every(_keys.contains) || json.keys.length != _keys.length) {
      return null;
    }
    return switch ((
      _toolName(json.raw('name')),
      json.raw('description'),
      JsonObject.parse(json.raw('input_schema')),
      json.raw('steps'),
    )) {
      (
        final name?,
        final String description,
        final schema?,
        final List<Object?> steps,
      ) =>
        switch ((Input.parse(schema), ToolAction._parse(steps))) {
          (final input?, final action?) => OneActionTool._(
            name,
            description,
            input,
            action,
          ),
          _ => null,
        },
      _ => null,
    };
  }

  static const _keys = {'name', 'description', 'input_schema', 'steps'};

  JsonObject toJson() => .of({
    'name': name.value,
    'description': description,
    'input_schema': input.schema,
    'steps': action._steps,
  });
}

/// The tool name [json] is, or null if it is none.
ToolName? _toolName(Object? json) =>
    json is String ? ToolName.parse(json) : null;

/// What a tool may propose. Each case is one kind of action the airlock
/// decides, and the agent loop turns each into the airlock's own program in
/// one exhaustive switch, so a new case is a deliberate change on both
/// sides.
sealed class ToolAction {
  const ToolAction();

  /// The action [steps] spells; null for anything else.
  static ToolAction? _parse(List<Object?> steps) => switch (steps) {
    [
      _propose,
      _Kind.fetch,
      final String origin,
      final String path,
      final signIn,
    ] =>
      switch ((
        Origin.parse(origin),
        path.isEmpty ? WebPath.root : WebPath.parse(path),
        _signIn(signIn),
      )) {
        (final origin?, final path?, final signIn?) => Fetch(
          origin,
          path,
          signIn,
        ),
        _ => null,
      },
    _ => null,
  };

  /// This action as `steps`.
  List<Object?> get _steps;
}

/// The sign-in [json] names, or null if it names none.
SignIn? _signIn(Object? json) {
  try {
    return decodeSignIn(json);
  } on FormatException {
    return null;
  }
}

/// A fetch of [path] on [origin], signed in as [signIn], whose response the
/// model reads as text.
final class Fetch extends ToolAction {
  const Fetch(this.origin, this.path, this.signIn);

  final Origin origin;
  final WebPath path;
  final SignIn signIn;

  @override
  List<Object?> get _steps => [
    _propose,
    _Kind.fetch,
    '$origin',
    path.value,
    encodeSignIn(signIn),
  ];
}

/// The form `steps` is written in.
const _propose = 'propose';

/// The names `steps` gives each kind of [ToolAction].
abstract final class _Kind {
  static const fetch = 'fetch';
}
