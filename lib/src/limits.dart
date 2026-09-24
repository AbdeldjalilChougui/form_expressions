/// Resource limits that protect the host from hostile or runaway input.
///
/// Expressions usually come from form definitions, which may be authored by
/// untrusted users. These limits bound the work done while compiling and
/// evaluating them.
class ExpressionLimits {
  /// Creates a set of limits. All values must be positive.
  const ExpressionLimits({
    this.maxLength = 4096,
    this.maxDepth = 64,
    this.maxTemplateLength = 65536,
  });

  /// Maximum number of characters in a single expression.
  final int maxLength;

  /// Maximum nesting depth of the syntax tree (parentheses, unary operators,
  /// function arguments, ternaries, lists) and of host data structures
  /// handed to the evaluator.
  final int maxDepth;

  /// Maximum number of characters in a template.
  final int maxTemplateLength;

  /// Throws an [ArgumentError] if any limit is not positive.
  void validate() {
    if (maxLength < 1) throw ArgumentError.value(maxLength, 'maxLength');
    if (maxDepth < 1) throw ArgumentError.value(maxDepth, 'maxDepth');
    if (maxTemplateLength < 1) {
      throw ArgumentError.value(maxTemplateLength, 'maxTemplateLength');
    }
  }
}
