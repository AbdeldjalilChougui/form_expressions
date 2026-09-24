part of 'engine.dart';

/// A compiled text template for piping answers into labels and messages.
///
/// Syntax:
///
/// * `{{ expr }}` inserts the value of any expression, for example
///   `{{name}}`, `{{address.city}}` or `{{price * qty}}`.
/// * `{{ expr | filter }}` passes the value through a function, with
///   optional extra arguments: `{{ name | trim | upper }}`,
///   `{{ ratio | round(2) }}`. Any built-in or registered function works as
///   a filter; the value becomes its first argument.
/// * `{{ name ?? "friend" }}` supplies a fallback for missing values.
/// * `\{{` produces a literal `{{`.
///
/// Values are formatted with the same rules as string concatenation: `null`
/// is empty, lists are joined with `", "`, integral numbers print without
/// `.0`, and dates at midnight print as `yyyy-MM-dd`.
class Template {
  Template._(this._engine, this.source, this._segments) {
    for (final segment in _segments) {
      if (segment is Node) {
        collectReferences(segment, variables: _variables, functions: {});
      }
    }
  }

  /// Parses [source] with the functions and limits of [engine].
  factory Template.parse(ExpressionEngine engine, String source) {
    final limits = engine.limits;
    if (source.length > limits.maxTemplateLength) {
      throw ParseError(
        'Template is too long (${source.length} characters, '
        'max ${limits.maxTemplateLength})',
        source: source,
        offset: limits.maxTemplateLength,
      );
    }
    final segments = <Object>[];
    final text = StringBuffer();
    var i = 0;
    while (i < source.length) {
      if (source.startsWith(r'\{{', i)) {
        text.write('{{');
        i += 3;
        continue;
      }
      if (!source.startsWith('{{', i)) {
        text.write(source[i]);
        i++;
        continue;
      }
      if (text.isNotEmpty) {
        segments.add(text.toString());
        text.clear();
      }
      final lexer = Lexer(source, start: i + 2, templateOpen: i);
      final tokens = lexer.tokenize();
      if (lexer.end - i > limits.maxLength) {
        throw ParseError(
          'Placeholder is too long (max ${limits.maxLength} characters)',
          source: source,
          offset: i,
        );
      }
      segments.add(Parser(
        tokens,
        source: source,
        limits: limits,
        functionArity: engine.arityOf,
      ).parseAll(allowPipes: true));
      i = lexer.end;
    }
    if (text.isNotEmpty) segments.add(text.toString());
    return Template._(engine, source, segments);
  }

  final ExpressionEngine _engine;

  /// Literal [String]s and placeholder [Node]s in order.
  final List<Object> _segments;
  final Set<String> _variables = {};

  /// The original template text.
  final String source;

  /// Every variable path referenced by any placeholder.
  Set<String> get variables => Set.unmodifiable(_variables);

  /// Renders the template.
  ///
  /// Variables come from [resolver] when given, otherwise from [variables].
  /// An [EvalError] in a placeholder is rethrown (its offset points into
  /// [source]) unless [onError] is given, in which case its return value is
  /// inserted instead.
  String render({
    Map<String, Object?> variables = const {},
    VariableResolver? resolver,
    String Function(EvalError error)? onError,
  }) {
    final out = StringBuffer();
    for (final segment in _segments) {
      if (segment is String) {
        out.write(segment);
        continue;
      }
      try {
        out.write(formatValue(_engine._evaluateNode(
          segment as Node,
          source,
          variables: variables,
          resolver: resolver,
        )));
      } on EvalError catch (e) {
        if (onError == null) rethrow;
        out.write(onError(e));
      }
    }
    return out.toString();
  }

  @override
  String toString() => 'Template($source)';
}
