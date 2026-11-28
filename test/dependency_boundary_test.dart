import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:checked_json/checked_json.dart';
import 'package:test/test.dart';

/// Every URI a source's directives name, in every branch, as written.
///
/// Read from the parse tree, which knows comments, strings and metadata, so
/// none of them can hide a directive or cut one short. The tree keeps every
/// branch of a conditional import (the element model keeps only the one it
/// picked), and `import 'stub.dart' if (dart.library.io) 'dart:io';` names
/// both.
Iterable<StringLiteral> directiveUris(String source) sync* {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  // Over every directive, unfiltered and exhaustive, so a new kind of
  // directive stops this compiling.
  for (final directive in unit.directives) {
    yield* switch (directive) {
      NamespaceDirective(:final uri, :final configurations) => [
        uri,
        for (final branch in configurations) branch.uri,
      ],
      PartDirective(:final uri) => [uri],
      LibraryDirective() || PartOfDirective() => const <StringLiteral>[],
    };
  }
}

const _allowedSdk = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

/// The only packages this one may need at run time: checked_json and
/// vocabularies, each named, so admitting one is a reviewed change rather
/// than a suffix that matches.
const _allowedPackages = {
  'checked_json',
  'is_model_vocabulary',
  'is_outcome_vocabulary',
  'is_sign_in_vocabulary',
  'is_web_address_vocabulary',
};

bool _allowed(String target) {
  final uri = Uri.parse(target);
  return switch (uri.scheme) {
    'dart' => _allowedSdk.contains(target),
    'package' => {
      ..._allowedPackages,
      'is_tool_definition_vocabulary',
    }.contains(uri.pathSegments.first),
    '' => !uri.isAbsolute && !uri.pathSegments.contains('..'),
    _ => false,
  };
}

/// Every package this one needs at run time, from pub's resolved graph:
/// its direct dependencies that are not dev ones, and everything they need.
Set<String> _runtimePackages() {
  final result = Process.runSync(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ]);
  if (result.exitCode != 0) throw StateError('pub deps: ${result.stderr}');
  final graph = JsonObject.decode('${result.stdout}');
  final packages = {
    for (final p in graph.objects('packages')) p.string('name'): p,
  };
  final root = packages[graph.string('root')]!;
  final found = <String>{};
  final toVisit = [
    for (final name in root.strings('dependencies'))
      if (packages[name]!.string('kind') == 'direct') name,
  ];
  while (toVisit.isNotEmpty) {
    final name = toVisit.removeLast();
    if (found.add(name)) {
      toVisit.addAll(packages[name]!.strings('dependencies'));
    }
  }
  return found;
}

void main() {
  test('shared contracts do not import runners, tools, clients or effects', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final literal in directiveUris(file.readAsStringSync())) {
        // Null when the URI is not one plain string, so cannot be checked.
        final target = literal.stringValue;
        if (target == null || !_allowed(target)) {
          violations.add('${file.path}: ${target ?? literal.toSource()}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'is_tool_definition_vocabulary supplies contracts, not clients, runners or effects',
    );
  });

  test(
    'everything needed at run time is checked_json or a named vocabulary',
    () {
      // A vocabulary that picked up an effects package would pass the import
      // check above, since only this package's own imports are read there.
      expect(_runtimePackages().difference(_allowedPackages), isEmpty);
    },
  );
}
