// Hardcoded-UI-string scanner (docs/i18n/TESTING.md, layer T2).
//
// Parses every Dart file under lib/ (syntax only, no type resolution) and reports string
// literals that look like user-facing English and have not been moved into the ARB files.
// It is both the extraction inventory and the regression gate (test/l10n/hardcoded_strings_test.dart).
//
//   dart run tool/l10n/scan.dart            summary per file
//   dart run tool/l10n/scan.dart --list     every finding, one per line
//   dart run tool/l10n/scan.dart --list lib/club/ui/settings_page.dart
//   dart run tool/l10n/scan.dart --write-baseline   re-pin test/l10n/hardcoded_baseline.txt
//   dart run tool/l10n/scan.dart --list --lower [path]   lowercase single words (manual audit)
//
// A literal is exempt when it sits in a structurally non-UI position (see [_Visitor]), when the
// line (or the line above) carries a `// l10n-ignore: <why>` comment, or when the file carries
// `// l10n-ignore-file: <why>` (files that hold only engine DSL verbs, wire names, and the like).
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// How confident the scanner is that a literal is user-facing.
enum Tier {
  /// Reaches a known UI sink (`Text(`, `tooltip:`, `labelText:` …).
  sink,

  /// Reads like prose (several words) somewhere else.
  prose,

  /// A single word outside any known sink: a label held in data, or an identifier.
  word,

  /// A single all-lowercase word outside any known sink ('now', 'bytes' — but mostly wire
  /// values and enum names). Too noisy for the gate; listed with `--lower` for a manual audit.
  lower,
}

class Finding {
  final String file;
  final int line;
  final Tier tier;
  final String text;
  const Finding(this.file, this.line, this.tier, this.text);
  @override
  String toString() => '$file:$line: [${tier.name}] $text';
}

/// Files that never hold translatable UI text.
bool _skipFile(String path) =>
    path.endsWith('.g.dart') ||
    path.contains('/l10n/app_localizations') ||
    path.contains('/dev/'); // memlab + battery counters: adb-only developer surfaces

/// Named arguments whose value is shown to the user.
const _sinkNames = {
  'tooltip', 'message', 'label', 'labelText', 'hintText', 'helperText', 'errorText',
  'counterText', 'prefixText', 'suffixText', 'semanticLabel', 'semanticsLabel', 'title',
  'subtitle', 'content', 'text', 'hint', 'name', 'note', 'caption', 'description',
  'confirmLabel', 'cancelLabel', 'actionLabel', 'dialogTitle', 'subject', 'body', 'header',
  'emptyText', 'emptyMessage', 'placeholder', 'tip', 'help', 'barrierLabel',
};

/// Constructors / functions whose positional string arguments are shown to the user.
const _sinkCalls = {
  'Text', 'SelectableText', 'Tooltip', 'SnackBar', 'TextSpan', 'ErrorView', 'EmptyView',
};

/// Calls whose string arguments are never UI text.
const _nonUiCalls = {
  'debugPrint', 'print', 'log', 'assert', 'RegExp', 'Key', 'ValueKey', 'PageStorageKey',
  'GlobalObjectKey', 'ObjectKey', 'MethodChannel', 'EventChannel', 'invokeMethod',
  'lookup', 'lookupFunction', 'toNativeUtf8', 'fromEnvironment', 'startsWith', 'endsWith',
  'contains', 'split', 'replaceAll', 'replaceFirst', 'indexOf', 'lastIndexOf', 'padLeft',
  'padRight', 'getString', 'setString', 'getBool', 'setBool', 'getInt', 'setInt',
  'getDouble', 'setDouble', 'getStringList', 'setStringList', 'remove', 'containsKey',
  'parse', 'tryParse', 'DateFormat', 'NumberFormat', 'StateError', 'ArgumentError',
  'UnsupportedError', 'AssertionError', 'UnimplementedError', 'RangeError',
  'FlutterError', 'debugFillProperties', 'join', 'open', 'DynamicLibrary',
  'removePrefix', 'trimPrefix', 'hasMatch', 'firstMatch', 'allMatches',
};

final _letters = RegExp(r'\p{L}{2,}', unicode: true);
final _dslCall = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*\(.*\)\s*$', dotAll: true);
final _identLike = RegExp(r'^[a-z0-9_./:\-#%@+=?&{}\[\]$*~^|\\]+$'); // lowercase tokens, paths, urls
final _path = RegExp(r'^/\S*$'); // REST routes: '/post/{}/parents'
// camelCase / dotted / snake identifiers that start lowercase: 'edit.selectAll', 'watchReplay'.
final _codeIdent = RegExp(r'^[a-z][A-Za-z0-9]*([._][A-Za-z0-9]+)+$|^[a-z]+[A-Z][A-Za-z0-9]*$');
final _lowerWord = RegExp(r'^[a-z]{2,}$');
final _url = RegExp(r'^(https?|mailto|file|package|dart|asset|assets|club\.makapix)[:/]');

class _Visitor extends RecursiveAstVisitor<void> {
  final String file;
  final LineInfo lines;
  final Set<int> ignoredLines;
  final List<Finding> out;
  final bool includeLower;
  _Visitor(this.file, this.lines, this.ignoredLines, this.out, {this.includeLower = false});

  @override
  void visitImportDirective(ImportDirective node) {}
  @override
  void visitExportDirective(ExportDirective node) {}
  @override
  void visitPartDirective(PartDirective node) {}
  @override
  void visitPartOfDirective(PartOfDirective node) {}
  @override
  void visitAnnotation(Annotation node) {}
  @override
  void visitAssertStatement(AssertStatement node) {}
  @override
  void visitAssertInitializer(AssertInitializer node) {}

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _check(node, node.value);

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    // 'a ' 'b' is one message: report it once, at the first line.
    final sb = StringBuffer();
    for (final s in node.strings) {
      sb.write(_flatten(s));
    }
    _check(node, sb.toString());
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _check(node, _flatten(node));
    // Literals nested inside ${...} expressions are separate candidates.
    for (final e in node.elements) {
      if (e is InterpolationExpression) e.expression.accept(this);
    }
  }

  String _flatten(StringLiteral s) {
    if (s is SimpleStringLiteral) return s.value;
    if (s is StringInterpolation) {
      return s.elements.map((e) => e is InterpolationString ? e.value : '{}').join();
    }
    if (s is AdjacentStrings) return s.strings.map(_flatten).join();
    return '';
  }

  void _check(AstNode node, String text) {
    final probe = text.replaceAll('{}', ' ').trim();
    if (!_letters.hasMatch(probe)) return;
    if (_url.hasMatch(probe)) return;
    if (_path.hasMatch(text)) return;
    if (_dslCall.hasMatch(text.trim())) return;
    if (_codeIdent.hasMatch(probe)) return;
    final line = lines.getLocation(node.offset).lineNumber;
    if (ignoredLines.contains(line)) return;
    if (_structurallyNonUi(node)) return;

    final inSink = _inSink(node);
    final words = probe.split(RegExp(r'\s+')).where(_letters.hasMatch).length;
    final Tier tier;
    if (inSink) {
      tier = Tier.sink;
    } else if (words >= 2) {
      tier = Tier.prose;
    } else {
      // 'now' alone is ambiguous; '{} frames' or '{}mo' (a word glued to a value, with
      // nothing but letters and spaces around it) is display text.
      final gluedToValue = text.contains('{}') &&
          RegExp(r'^[\p{L} ]+$', unicode: true).hasMatch(text.replaceAll('{}', ''));
      if (gluedToValue) {
        tier = Tier.word;
      } else if (_lowerWord.hasMatch(probe)) {
        if (!includeLower) return;
        tier = Tier.lower;
      } else {
        if (_identLike.hasMatch(probe)) return; // 'image/png', 'club_locale', 'v2'
        tier = Tier.word;
      }
    }
    out.add(Finding(file, line, tier, text.replaceAll('\n', r'\n')));
  }

  /// Walks up through expression wrappers that pass a string along unchanged.
  AstNode _carrier(AstNode node) {
    var n = node;
    while (true) {
      final p = n.parent;
      if (p is ParenthesizedExpression ||
          p is ConditionalExpression && p.condition != n ||
          p is BinaryExpression && (p.operator.lexeme == '+' || p.operator.lexeme == '??') ||
          p is InterpolationExpression ||
          p is StringInterpolation ||
          p is AdjacentStrings ||
          p is SwitchExpressionCase && p.expression == n ||
          p is SwitchExpression) {
        n = p!;
      } else {
        return n;
      }
    }
  }

  bool _structurallyNonUi(AstNode node) {
    final c = _carrier(node);
    final p = c.parent;
    // == / != operands, relational patterns.
    if (p is BinaryExpression && (p.operator.lexeme == '==' || p.operator.lexeme == '!=')) return true;
    if (p is ConstantPattern || p is RelationalPattern) return true;
    if (p is SwitchCase) return true;
    // json['key'] and {'key': value} keys.
    if (p is IndexExpression && p.index == c) return true;
    if (p is MapLiteralEntry && p.key == c) {
      // A map keyed by display text is unusual; values are still checked.
      return true;
    }
    if (p is MapPatternEntry) return true;
    // Arguments of known non-UI calls.
    final call = _enclosingCallName(c);
    if (call != null && _nonUiCalls.contains(call)) return true;
    // throw X('...') — developer-facing unless caught and shown; ClubError-style user errors
    // are built by named constructors and audited separately.
    for (AstNode? a = c; a != null; a = a.parent) {
      if (a is ThrowExpression) return true;
      if (a is FunctionBody) break;
    }
    return false;
  }

  String? _enclosingCallName(AstNode c) {
    var p = c.parent;
    if (p is NamedArgument) p = p.parent;
    if (p is ArgumentList) {
      final owner = p.parent;
      if (owner is MethodInvocation) return owner.methodName.name;
      if (owner is InstanceCreationExpression) return owner.constructorName.type.name.lexeme;
      if (owner is FunctionExpressionInvocation) return null;
    }
    return null;
  }

  bool _inSink(AstNode node) {
    final c = _carrier(node);
    final p = c.parent;
    if (p is NamedArgument && _sinkNames.contains(p.name.lexeme)) return true;
    final call = _enclosingCallName(c);
    if (call != null && (_sinkCalls.contains(call) || call.startsWith('_snack') || call.startsWith('showSnack') || call == '_toast' || call == 'snack')) {
      return true;
    }
    return false;
  }
}

/// Scans [root] (a directory or a single file) and returns the findings, sorted.
List<Finding> scan(String root, {bool includeLower = false}) {
  final files = <File>[];
  final type = FileSystemEntity.typeSync(root);
  if (type == FileSystemEntityType.file) {
    files.add(File(root));
  } else {
    files.addAll(Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')));
  }
  final out = <Finding>[];
  for (final f in files) {
    final path = f.path.replaceAll('\\', '/');
    if (_skipFile(path)) continue;
    final src = f.readAsStringSync();
    if (src.contains('l10n-ignore-file')) continue;
    final unit = parseString(content: src, path: path, throwIfDiagnostics: false).unit;
    final ignored = <int>{};
    final srcLines = src.split('\n');
    for (var i = 0; i < srcLines.length; i++) {
      if (srcLines[i].contains('l10n-ignore')) {
        ignored.add(i + 1);
        // A comment on its own line exempts the next line too.
        if (srcLines[i].trimLeft().startsWith('//')) ignored.add(i + 2);
      }
    }
    unit.accept(_Visitor(path, unit.lineInfo, ignored, out, includeLower: includeLower));
  }
  out.sort((a, b) {
    final c = a.file.compareTo(b.file);
    return c != 0 ? c : a.line.compareTo(b.line);
  });
  return out;
}

/// Where the per-file finding counts are pinned while the extraction is in progress.
const String baselinePath = 'test/l10n/hardcoded_baseline.txt';

/// Findings per file, as `path → count`.
Map<String, int> countsByFile(List<Finding> findings) {
  final out = <String, int>{};
  for (final f in findings) {
    out[f.file] = (out[f.file] ?? 0) + 1;
  }
  return out;
}

/// Parses the baseline file: `<count> <path>` per line, `#` comments.
Map<String, int> readBaseline() {
  final file = File(baselinePath);
  if (!file.existsSync()) return {};
  final out = <String, int>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final sp = t.indexOf(' ');
    out[t.substring(sp + 1).trim()] = int.parse(t.substring(0, sp));
  }
  return out;
}

void writeBaseline(Map<String, int> counts) {
  final rows = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  final sb = StringBuffer()
    ..writeln('# Hardcoded-string baseline (docs/i18n/PLAN.md): strings the scanner still finds in each')
    ..writeln('# file. test/l10n/hardcoded_strings_test.dart fails if a file has MORE than its number (a')
    ..writeln('# new hardcoded string) or FEWER (strings were extracted: re-pin with')
    ..writeln('# `dart run tool/l10n/scan.dart --write-baseline`). Done when this file is empty.')
    ..writeln('# total $total in ${counts.length} files');
  for (final e in rows) {
    sb.writeln('${e.value} ${e.key}');
  }
  File(baselinePath).writeAsStringSync(sb.toString());
}

void main(List<String> args) {
  if (args.contains('--write-baseline')) {
    final counts = countsByFile(scan('lib'));
    writeBaseline(counts);
    stdout.writeln('wrote $baselinePath: ${counts.values.fold<int>(0, (a, b) => a + b)} in ${counts.length} files');
    return;
  }
  final list = args.contains('--list');
  final paths = args.where((a) => !a.startsWith('--')).toList();
  final lower = args.contains('--lower');
  final findings = [
    for (final p in paths.isEmpty ? ['lib'] : paths) ...scan(p, includeLower: lower),
  ];
  if (lower) findings.removeWhere((f) => f.tier != Tier.lower);
  if (list) {
    findings.forEach(stdout.writeln);
  } else {
    final byFile = <String, List<Finding>>{};
    for (final f in findings) {
      (byFile[f.file] ??= []).add(f);
    }
    final rows = byFile.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in rows) {
      int n(Tier t) => e.value.where((f) => f.tier == t).length;
      stdout.writeln('${e.value.length.toString().padLeft(4)}  sink ${n(Tier.sink).toString().padLeft(3)}  '
          'prose ${n(Tier.prose).toString().padLeft(3)}  word ${n(Tier.word).toString().padLeft(3)}  ${e.key}');
    }
  }
  int n(Tier t) => findings.where((f) => f.tier == t).length;
  stdout.writeln('TOTAL ${findings.length}  (sink ${n(Tier.sink)}, prose ${n(Tier.prose)}, word ${n(Tier.word)}, lower ${n(Tier.lower)}) '
      'in ${findings.map((f) => f.file).toSet().length} files');
}
