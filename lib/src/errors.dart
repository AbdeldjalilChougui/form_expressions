/// Base class of every error reported by this package.
///
/// Carries the [source] text and the zero-based character [offset] of the
/// problem so hosts can highlight it. [line] and [column] are one-based.
abstract class ExpressionError implements Exception {
  /// Creates an error at [offset] inside [source].
  ExpressionError(this.message, {required this.source, required this.offset});

  /// Human readable description of the problem.
  final String message;

  /// The full source text (expression or template) the error refers to.
  final String source;

  /// Zero-based character offset into [source].
  final int offset;

  /// One-based line number of [offset].
  int get line => _lineCol.$1;

  /// One-based column number of [offset].
  int get column => _lineCol.$2;

  (int, int) get _lineCol {
    var line = 1;
    var lineStart = 0;
    final end = offset.clamp(0, source.length);
    for (var i = 0; i < end; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return (line, end - lineStart + 1);
  }

  /// Short label used by [toString], such as `ParseError`.
  String get kind;

  @override
  String toString() {
    final lines = source.split('\n');
    final text = line - 1 < lines.length ? lines[line - 1] : '';
    return '$kind: $message at line $line, column $column\n'
        '  $text\n'
        '  ${' ' * (column - 1)}^';
  }
}

/// The source text is not a valid expression or template.
///
/// Thrown by `ExpressionEngine.compile` and `ExpressionEngine.template`.
class ParseError extends ExpressionError {
  /// Creates a parse error at [offset] inside [source].
  ParseError(super.message, {required super.source, required super.offset});

  @override
  String get kind => 'ParseError';
}

/// Evaluation failed: a type mismatch, division by zero, a failing function,
/// or host data the sandbox does not accept.
class EvalError extends ExpressionError {
  /// Creates an evaluation error at [offset] inside [source].
  EvalError(super.message, {required super.source, required super.offset});

  @override
  String get kind => 'EvalError';
}

/// Internal signal thrown by built-in helpers; the evaluator attaches the
/// position and rethrows it as an [EvalError].
class EvalFailure implements Exception {
  /// Creates a failure with [message].
  EvalFailure(this.message);

  /// Description without position information.
  final String message;

  @override
  String toString() => message;
}
