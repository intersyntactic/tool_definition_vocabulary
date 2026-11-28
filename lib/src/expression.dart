import 'dart:convert';

import 'package:checked_json/checked_json.dart';

/// One expression of a tool's steps: the part of TEL, the tool expression
/// language, that builds a JSON value from literals and a call's input.
///
/// A string, whole number or boolean is itself. Every array is a form:
/// `["input", <field>]` reads one field of the call,
/// `["record", <key>, <expression>, …]` builds an object whose keys are
/// written out, and `["list", <expression>…]` builds an array. So a literal
/// array or object is written as a `list` or a `record`, and no literal is
/// ever read as a reference.
sealed class Expression {
  const Expression();

  /// The deepest an expression nests, counting each form; deeper is
  /// refused, so a recursive reader cannot run out of stack.
  static const maxDepth = 64;

  /// The most UTF-8 bytes a literal string holds.
  static const maxTextBytes = 64 * 1024;

  /// The most expressions a `list` holds.
  static const maxListLength = 1000;

  /// The largest whole number a literal is, either side of zero: 2^53 - 1,
  /// the bound checked_json reads JSON to, so a web build reads it exactly.
  static const maxInteger = 9007199254740991;

  /// The expression [json] spells, or null for anything else: an unknown
  /// form, a null or fractional number, a record key written twice, or a
  /// value past one of the bounds above.
  static Expression? parse(Object? json) => _parse(json, 1);

  /// [json] as an expression with no references: an object becomes a
  /// `record` and an array a `list`. Null when [json] holds a value no
  /// expression can, such as null or a fraction.
  static Expression? quoting(Object? json) => _quote(json, 1);

  /// A literal string. An [ArgumentError] past [maxTextBytes].
  factory Expression.text(String value) =>
      TextExpression._check(value) ??
      (throw ArgumentError.value(
        value,
        'value',
        'is over $maxTextBytes bytes',
      ));

  /// A literal whole number. An [ArgumentError] past [maxInteger].
  factory Expression.integer(int value) =>
      IntegerExpression._check(value) ??
      (throw ArgumentError.value(value, 'value', 'is past ±$maxInteger'));

  /// A literal boolean.
  factory Expression.boolean(bool value) => BooleanExpression._(value);

  /// The call's [field].
  factory Expression.input(String field) =>
      InputFieldExpression._check(field) ??
      (throw ArgumentError.value(field, 'field', 'is empty'));

  /// An object of [entries], in their order. An [ArgumentError] for an
  /// empty key, or an expression that would nest past [maxDepth].
  factory Expression.record(Map<String, Expression> entries) => _checkedDepth(
    RecordExpression._check([
          for (final e in entries.entries) (e.key, e.value),
        ]) ??
        (throw ArgumentError.value(entries, 'entries', 'has an empty key')),
  );

  /// An array of [items]. An [ArgumentError] past [maxListLength], or a
  /// expression that would nest past [maxDepth].
  factory Expression.list(List<Expression> items) => _checkedDepth(
    ListExpression._check(items) ??
        (throw ArgumentError.value(
          items.length,
          'items',
          'is over $maxListLength',
        )),
  );

  /// The fields of the call this expression reads.
  Set<String> get inputFields;

  /// How many forms deep this expression nests; a literal is 0.
  int get _depth;

  /// The JSON value this expression builds from [call], a call as a tool's
  /// input read it, so every field the expression reads is one the input
  /// checked.
  Object? filledFrom(JsonObject call);

  /// This expression as `steps` spells it.
  Object? toJson();
}

Expression _checkedDepth(Expression expression) =>
    expression._depth <= Expression.maxDepth
    ? expression
    : throw ArgumentError('the expression nests past ${Expression.maxDepth}');

Expression? _parse(Object? json, int depth) => switch (json) {
  final String s => TextExpression._check(s),
  final int i => IntegerExpression._check(i),
  final bool b => BooleanExpression._(b),
  final List<Object?> _ when depth > Expression.maxDepth => null,
  [_Form.input, final String field] => InputFieldExpression._check(field),
  [_Form.record, ...final rest] => _record(rest, depth),
  [_Form.list, ...final rest] => _list(rest, depth),
  _ => null,
};

Expression? _record(List<Object?> rest, int depth) {
  if (rest.length.isOdd) return null;
  final entries = <(String, Expression)>[];
  for (var i = 0; i < rest.length; i += 2) {
    final (key, value) = (rest[i], _parse(rest[i + 1], depth + 1));
    if (key is! String || value == null) return null;
    entries.add((key, value));
  }
  return RecordExpression._check(entries);
}

Expression? _list(List<Object?> rest, int depth) {
  final items = <Expression>[];
  for (final item in rest) {
    final expression = _parse(item, depth + 1);
    if (expression == null) return null;
    items.add(expression);
  }
  return ListExpression._check(items);
}

Expression? _quote(Object? json, int depth) {
  if (depth > Expression.maxDepth) return null;
  switch (json) {
    case String() || int() || bool():
      return _parse(json, depth);
    case final List<Object?> l:
      final items = <Expression>[];
      for (final item in l) {
        final expression = _quote(item, depth + 1);
        if (expression == null) return null;
        items.add(expression);
      }
      return ListExpression._check(items);
  }
  final object = JsonObject.parse(json);
  if (object == null) return null;
  final entries = <(String, Expression)>[];
  for (final key in object.keys) {
    final expression = _quote(object.raw(key), depth + 1);
    if (expression == null) return null;
    entries.add((key, expression));
  }
  return RecordExpression._check(entries);
}

/// A literal string.
final class TextExpression extends Expression {
  const TextExpression._(this.value);

  static TextExpression? _check(String value) =>
      utf8.encode(value).length <= Expression.maxTextBytes
      ? TextExpression._(value)
      : null;

  final String value;

  @override
  Set<String> get inputFields => const {};

  @override
  int get _depth => 0;

  @override
  Object? filledFrom(JsonObject call) => value;

  @override
  Object? toJson() => value;
}

/// A literal whole number.
final class IntegerExpression extends Expression {
  const IntegerExpression._(this.value);

  static IntegerExpression? _check(int value) =>
      value.abs() <= Expression.maxInteger ? IntegerExpression._(value) : null;

  final int value;

  @override
  Set<String> get inputFields => const {};

  @override
  int get _depth => 0;

  @override
  Object? filledFrom(JsonObject call) => value;

  @override
  Object? toJson() => value;
}

/// A literal boolean.
final class BooleanExpression extends Expression {
  const BooleanExpression._(this.value);

  final bool value;

  @override
  Set<String> get inputFields => const {};

  @override
  int get _depth => 0;

  @override
  Object? filledFrom(JsonObject call) => value;

  @override
  Object? toJson() => value;
}

/// One field of the call, `["input", <field>]`.
final class InputFieldExpression extends Expression {
  const InputFieldExpression._(this.field);

  static InputFieldExpression? _check(String field) =>
      field.isEmpty ? null : InputFieldExpression._(field);

  final String field;

  @override
  Set<String> get inputFields => {field};

  @override
  int get _depth => 1;

  @override
  Object? filledFrom(JsonObject call) => call.raw(field);

  @override
  Object? toJson() => [_Form.input, field];
}

/// An object, `["record", <key>, <expression>, …]`, its keys written out.
final class RecordExpression extends Expression {
  RecordExpression._(List<(String, Expression)> entries)
    : entries = List.unmodifiable(entries);

  /// Null for an empty key or one written twice.
  static RecordExpression? _check(List<(String, Expression)> entries) {
    final keys = <String>{};
    for (final (key, _) in entries) {
      if (key.isEmpty || !keys.add(key)) return null;
    }
    return RecordExpression._(entries);
  }

  final List<(String, Expression)> entries;

  @override
  Set<String> get inputFields => {
    for (final (_, expression) in entries) ...expression.inputFields,
  };

  @override
  int get _depth =>
      1 +
      entries.fold(
        0,
        (deepest, e) => deepest > e.$2._depth ? deepest : e.$2._depth,
      );

  @override
  Object? filledFrom(JsonObject call) => {
    for (final (key, expression) in entries) key: expression.filledFrom(call),
  };

  @override
  Object? toJson() => [
    _Form.record,
    for (final (key, expression) in entries) ...[key, expression.toJson()],
  ];
}

/// An array, `["list", <expression>…]`.
final class ListExpression extends Expression {
  ListExpression._(List<Expression> items) : items = List.unmodifiable(items);

  static ListExpression? _check(List<Expression> items) =>
      items.length <= Expression.maxListLength ? ListExpression._(items) : null;

  final List<Expression> items;

  @override
  Set<String> get inputFields => {for (final t in items) ...t.inputFields};

  @override
  int get _depth =>
      1 +
      items.fold(0, (deepest, t) => deepest > t._depth ? deepest : t._depth);

  @override
  Object? filledFrom(JsonObject call) => [
    for (final t in items) t.filledFrom(call),
  ];

  @override
  Object? toJson() => [_Form.list, for (final t in items) t.toJson()];
}

/// The names of TEL's forms that a [Expression] reads.
abstract final class _Form {
  static const input = 'input';
  static const record = 'record';
  static const list = 'list';
}
