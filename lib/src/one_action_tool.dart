import 'dart:convert';

import 'package:checked_json/checked_json.dart';

import 'input.dart';

/// A tool sent as data whose steps are one proposed action: its name,
/// description and [input], the [bound] values a person fixed for it, and
/// the [action] it proposes with its [arguments].
///
/// On the wire it is one JSON object, `name`, `description`,
/// `input_schema`, `bound` and `steps`, where `steps` is
/// `["propose", <action>, <argument>…]`. Each argument is a bound value
/// `["bound", k]`, an input field `["input", k]` or a literal, so every
/// string is literal text. A reference is checked when the tool is made: a
/// bound name against [bound], and an input name against the fields every
/// read of [input] gives a value for, so an argument is never missing when a
/// call is carried out.
final class OneActionTool {
  OneActionTool._(
    this.name,
    this.description,
    this.input,
    this.bound,
    this.action,
    this.arguments,
  );

  final String name;
  final String description;

  /// What a call takes, read back from its schema, so the schema the model
  /// is shown and the checker of what it sent are one description.
  final Input<JsonObject> input;

  /// Values fixed when the tool was made, such as a drive's id. The model
  /// never sends them.
  final Map<String, Literal> bound;

  /// The name of the action the tool proposes.
  final String action;

  final List<ActionArgument> arguments;

  /// The tool made in Dart, from the [input] its module built. An
  /// [ArgumentError] for an empty [name] or [action], or a reference that
  /// names no bound value or no field every read gives a value for.
  factory OneActionTool.of({
    required String name,
    required String description,
    required Input<Object?> input,
    Map<String, Literal> bound = const {},
    required String action,
    required List<ActionArgument> arguments,
  }) {
    final tool = OneActionTool._(
      name,
      description,
      // An Input's own schema is always one Input.parse reads.
      Input.parse(input.schema)!,
      Map.unmodifiable(bound),
      action,
      List.unmodifiable(arguments),
    );
    if (tool._problem() case final problem?) throw ArgumentError(problem);
    return tool;
  }

  /// The tool [json] describes, as [toJson] writes it; null for any other
  /// object.
  static OneActionTool? parse(JsonObject json) {
    if (!json.keys.every(_keys.contains) || json.keys.length != _keys.length) {
      return null;
    }
    final (name, description) = (json.raw('name'), json.raw('description'));
    if (name is! String || description is! String) return null;
    final input = switch (JsonObject.parse(json.raw('input_schema'))) {
      final schema? => Input.parse(schema),
      null => null,
    };
    final boundJson = JsonObject.parse(json.raw('bound'));
    final steps = switch (json.raw('steps')) {
      final List<Object?> l => l,
      _ => null,
    };
    if (input == null || boundJson == null || steps == null) return null;

    final bound = <String, Literal>{};
    for (final k in boundJson.keys) {
      final value = Literal.parse(boundJson.raw(k));
      if (value == null) return null;
      bound[k] = value;
    }
    final propose = switch (steps) {
      [_Form.propose, final String action, ...final rest] => (action, rest),
      _ => null,
    };
    if (propose == null) return null;
    final (action, rest) = propose;
    final arguments = <ActionArgument>[];
    for (final a in rest) {
      final argument = ActionArgument.parse(a);
      if (argument == null) return null;
      arguments.add(argument);
    }
    final tool = OneActionTool._(
      name,
      description,
      input,
      Map.unmodifiable(bound),
      action,
      List.unmodifiable(arguments),
    );
    return tool._problem() == null ? tool : null;
  }

  static const _keys = {
    'name',
    'description',
    'input_schema',
    'bound',
    'steps',
  };

  /// Why this tool is not a valid one, or null when it is.
  String? _problem() {
    if (name.isEmpty) return 'the name is empty';
    if (action.isEmpty) return 'the action is empty';
    for (final a in arguments) {
      switch (a) {
        case BoundReference(:final name) when !bound.containsKey(name):
          return '`$name` is not a bound value';
        case InputReference(:final name)
            when !input.namesAlwaysRead.contains(name):
          return '`$name` is not an input field that is required or has a '
              'default';
        case BoundReference() || InputReference() || Literal():
      }
    }
    return null;
  }

  /// The action's arguments for one call: [call] read by [input], with each
  /// reference filled in. A [JsonFieldException] if [input] refuses [call].
  List<Object> argumentsFor(JsonObject call) {
    final read = input.read(call);
    return [
      for (final a in arguments)
        switch (a) {
          // Both kinds of reference were checked when the tool was made.
          BoundReference(:final name) => bound[name]!.json,
          InputReference(:final name) => read.raw(name)!,
          Literal(:final json) => json,
        },
    ];
  }

  JsonObject toJson() => .of({
    'name': name,
    'description': description,
    'input_schema': input.schema,
    'bound': {
      for (final MapEntry(:key, :value) in bound.entries) key: value.json,
    },
    'steps': [_Form.propose, action, for (final a in arguments) a._json],
  });
}

/// One argument of a proposed action, as `steps` spells it.
sealed class ActionArgument {
  const ActionArgument();

  /// The argument [json] spells; null for anything else.
  static ActionArgument? parse(Object? json) => switch (json) {
    [_Form.bound, final String name] => BoundReference(name),
    [_Form.input, final String name] => InputReference(name),
    _ => Literal.parse(json),
  };

  Object get _json;
}

/// The bound value named [name].
final class BoundReference extends ActionArgument {
  const BoundReference(this.name);
  final String name;

  @override
  Object get _json => [_Form.bound, name];
}

/// The value of the input field named [name].
final class InputReference extends ActionArgument {
  const InputReference(this.name);
  final String name;

  @override
  Object get _json => [_Form.input, name];
}

/// A value written out: a string of at most 64 KiB in UTF-8, a whole number
/// within ±2^53, or true or false.
final class Literal extends ActionArgument {
  Literal._(this.json);

  /// The value as JSON: a [String], an [int] or a [bool].
  final Object json;

  /// An [ArgumentError] for a string over 64 KiB.
  factory Literal.text(String text) =>
      parse(text) ??
      (throw ArgumentError.value(text, 'text', 'is over 64 KiB'));

  /// An [ArgumentError] for a number outside ±2^53.
  factory Literal.integer(int n) =>
      parse(n) ?? (throw ArgumentError.value(n, 'n', 'is outside ±2^53'));

  factory Literal.boolean(bool b) => Literal._(b);

  /// The literal [json] is; null for anything else, a list or an object
  /// among them.
  static Literal? parse(Object? json) => switch (json) {
    final String s when utf8.encode(s).length <= _maxTextBytes => Literal._(s),
    final bool b => Literal._(b),
    _ => switch (wholeNumber(json)) {
      final n? when n > -_twoTo53 && n < _twoTo53 => Literal._(n),
      _ => null,
    },
  };

  @override
  Object get _json => json;
}

/// The names of the forms `steps` is written in.
abstract final class _Form {
  static const propose = 'propose';
  static const bound = 'bound';
  static const input = 'input';
}

const _maxTextBytes = 64 * 1024;

/// 2^53, written out so a web build reads it exactly.
const _twoTo53 = 9007199254740992;
