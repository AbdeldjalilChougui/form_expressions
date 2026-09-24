import 'dart:math' as math;

import 'ast.dart';
import 'errors.dart';
import 'functions.dart';
import 'lexer.dart' show maxSafeInt;
import 'values.dart';

/// Resolves a variable's dotted path (such as `address.city`) to a value.
///
/// Return `null` for unknown variables. Returned values must be `null`, a
/// [num], [String], [bool], [DateTime], an [Iterable] or a [Map] of those.
typedef VariableResolver = Object? Function(String path);

/// Walks the syntax tree and computes its value.
///
/// Evaluation never runs host code other than the [resolver] and registered
/// functions, and every failure surfaces as an [EvalError].
class Evaluator {
  /// Creates an evaluator.
  Evaluator({
    required this.source,
    required this.resolver,
    required this.functions,
    required this.maxDepth,
  });

  /// Source text used for error reports.
  final String source;

  /// Variable lookup.
  final VariableResolver resolver;

  /// Function table (lower-cased names).
  final Map<String, FunctionDefinition> functions;

  /// Maximum nesting accepted in host data.
  final int maxDepth;

  EvalError _error(String message, int offset) =>
      EvalError(message, source: source, offset: offset);

  /// Evaluates [node].
  Object? evaluate(Node node) {
    switch (node) {
      case LiteralNode(:final value):
        return value;
      case ListNode(:final items):
        return List<Object?>.unmodifiable(items.map(evaluate));
      case VariableNode():
        return _variable(node);
      case UnaryNode():
        return _unary(node);
      case BinaryNode():
        return _binaryChain(node);
      case ConditionalNode(:final condition, :final then, :final otherwise):
        return truthy(evaluate(condition), condition.start)
            ? evaluate(then)
            : evaluate(otherwise);
      case CallNode():
        return _call(node);
      case IndexNode():
        return _index(node);
    }
  }

  /// Interprets [value] as a condition: bools as themselves, `null` as false;
  /// anything else is an error at [offset].
  bool truthy(Object? value, int offset) {
    if (value is bool) return value;
    if (value == null) return false;
    throw _error('Expected a bool condition, got ${typeName(value)}', offset);
  }

  Object? _variable(VariableNode node) {
    Object? raw;
    try {
      raw = resolver(node.path);
    } on ExpressionError {
      rethrow;
    } catch (e) {
      throw _error("Could not resolve '${node.path}': $e", node.start);
    }
    try {
      return normalizeValue(raw, maxDepth);
    } on EvalFailure catch (e) {
      throw _error("Variable '${node.path}': ${e.message}", node.start);
    }
  }

  Object? _unary(UnaryNode node) {
    final value = evaluate(node.operand);
    switch (node.op) {
      case UnaryOp.not:
        return !truthy(value, node.operand.start);
      case UnaryOp.neg:
      case UnaryOp.pos:
        if (value is! num) {
          final symbol = node.op == UnaryOp.neg ? '-' : '+';
          throw _error(
              "Cannot apply '$symbol' to ${typeName(value)}", node.start);
        }
        return node.op == UnaryOp.neg ? -value : value;
    }
  }

  /// Evaluates a left-leaning chain of binary operators iteratively so long
  /// flat expressions such as `1 + 1 + ... + 1` do not recurse deeply.
  Object? _binaryChain(BinaryNode top) {
    final spine = <BinaryNode>[top];
    var leftmost = top.left;
    while (leftmost is BinaryNode) {
      spine.add(leftmost);
      leftmost = leftmost.left;
    }
    var value = evaluate(leftmost);
    for (var i = spine.length - 1; i >= 0; i--) {
      value = _binary(spine[i], value);
    }
    return value;
  }

  Object? _binary(BinaryNode node, Object? left) {
    switch (node.op) {
      case BinaryOp.and:
        if (!truthy(left, node.left.start)) return false;
        return truthy(evaluate(node.right), node.right.start);
      case BinaryOp.or:
        if (truthy(left, node.left.start)) return true;
        return truthy(evaluate(node.right), node.right.start);
      case BinaryOp.nullish:
        return left ?? evaluate(node.right);
      default:
        break;
    }
    final right = evaluate(node.right);
    switch (node.op) {
      case BinaryOp.eq:
        return valuesEqual(left, right);
      case BinaryOp.neq:
        return !valuesEqual(left, right);
      case BinaryOp.lt:
      case BinaryOp.lte:
      case BinaryOp.gt:
      case BinaryOp.gte:
        return _compare(node, left, right);
      case BinaryOp.inList:
      case BinaryOp.notIn:
        final found = _in(node, left, right);
        return node.op == BinaryOp.inList ? found : !found;
      default:
        return _arithmetic(node, left, right);
    }
  }

  bool _in(BinaryNode node, Object? needle, Object? haystack) {
    if (haystack == null) return false;
    if (haystack is List<Object?> || haystack is String) {
      if (haystack is String && needle is! String) {
        throw _error(
            "Cannot use 'in' to look for ${typeName(needle)} in a string",
            node.start);
      }
      return containsValue(haystack, needle);
    }
    throw _error(
        "Right side of 'in' must be a list or string, got "
        '${typeName(haystack)}',
        node.start);
  }

  bool _compare(BinaryNode node, Object? left, Object? right) {
    if (left == null || right == null) return false;
    int cmp;
    if (left is num && right is num) {
      cmp = left.compareTo(right);
      if (left == right) cmp = 0; // -0.0 vs 0.0
    } else if (left is String && right is String) {
      cmp = left.compareTo(right);
    } else if (left is DateTime && right is DateTime) {
      cmp = left.compareTo(right);
    } else {
      throw _error(
          'Cannot compare ${typeName(left)} and ${typeName(right)} '
          "with '${node.op.symbol}'",
          node.start);
    }
    return switch (node.op) {
      BinaryOp.lt => cmp < 0,
      BinaryOp.lte => cmp <= 0,
      BinaryOp.gt => cmp > 0,
      _ => cmp >= 0,
    };
  }

  Object? _arithmetic(BinaryNode node, Object? left, Object? right) {
    final symbol = node.op.symbol;
    if (node.op == BinaryOp.add && (left is String || right is String)) {
      return formatValue(left) + formatValue(right);
    }
    if (left is! num || right is! num) {
      final hint = left == null || right == null
          ? ' (use ?? to give empty values a default)'
          : '';
      throw _error(
          "Cannot apply '$symbol' to ${typeName(left)} and "
          '${typeName(right)}$hint',
          node.start);
    }
    final num result;
    switch (node.op) {
      case BinaryOp.add:
        result = _intSafe(left, right, (a, b) => a + b);
      case BinaryOp.sub:
        result = _intSafe(left, right, (a, b) => a - b);
      case BinaryOp.mul:
        result = _intSafe(left, right, (a, b) => a * b);
      case BinaryOp.div:
        if (right == 0) throw _error('Division by zero', node.start);
        result = left / right;
      case BinaryOp.mod:
        if (right == 0) throw _error('Division by zero', node.start);
        result = left % right;
      case BinaryOp.pow:
        final p = math.pow(left.toDouble(), right.toDouble());
        result =
            (left is int && right is int && right >= 0) ? tidyNumber(p) : p;
      default:
        throw StateError('Unhandled operator $symbol');
    }
    if (!result.isFinite) {
      throw _error("Result of '$symbol' is not a finite number", node.start);
    }
    return result;
  }

  /// Applies [op] keeping integers exact, but switches to doubles when the
  /// result would leave the exactly representable integer range instead of
  /// silently wrapping around.
  static num _intSafe(num a, num b, num Function(num, num) op) {
    if (a is int && b is int) {
      final estimate = op(a.toDouble(), b.toDouble());
      if (estimate.abs() > maxSafeInt) return estimate;
    }
    return op(a, b);
  }

  Object? _call(CallNode node) {
    if (node.name == 'if') {
      final cond = truthy(evaluate(node.args[0]), node.args[0].start);
      if (cond) return evaluate(node.args[1]);
      return node.args.length > 2 ? evaluate(node.args[2]) : null;
    }
    final def = functions[node.name];
    if (def == null) {
      // Only possible if a function was removed after compiling.
      throw _error("Unknown function '${node.name}'", node.start);
    }
    final args = node.args.map(evaluate).toList(growable: false);
    Object? result;
    try {
      result = def.body(List<Object?>.unmodifiable(args));
    } on EvalFailure catch (e) {
      throw _error(e.message, node.start);
    } on ExpressionError {
      rethrow;
    } catch (e) {
      throw _error('Function ${node.name}() failed: $e', node.start);
    }
    try {
      final normalized = normalizeValue(result, maxDepth);
      if (normalized is double && !normalized.isFinite) {
        throw EvalFailure('returned a non-finite number');
      }
      return normalized;
    } on EvalFailure catch (e) {
      throw _error(
          'Function ${node.name}() returned an unsupported value: '
          '${e.message}',
          node.start);
    }
  }

  Object? _index(IndexNode node) {
    final target = evaluate(node.target);
    final index = evaluate(node.index);
    if (target == null) return null;
    if (target is List<Object?> || target is String) {
      if (index is! num || index != index.truncateToDouble()) {
        throw _error('Index must be an integer, got ${typeName(index)}',
            node.index.start);
      }
      final i = index.toInt();
      if (target is List<Object?>) {
        return i >= 0 && i < target.length ? target[i] : null;
      }
      final s = target as String;
      return i >= 0 && i < s.length ? s[i] : null;
    }
    if (target is Map<Object?, Object?>) {
      return target[index is num ? formatValue(index) : index];
    }
    throw _error('Cannot index a ${typeName(target)}', node.start);
  }
}
