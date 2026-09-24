import 'dart:math' as math;

import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

/// A random arithmetic tree that knows both how to print itself and how to
/// compute its value with Dart's own operators.
sealed class _Node {
  num get value;

  /// Precedence of the printed form: higher binds tighter.
  int get precedence;

  /// Prints with the fewest parentheses the grammar allows.
  String minimal();

  /// Prints every sub-expression in parentheses.
  String full();
}

class _Lit extends _Node {
  _Lit(this.value);
  @override
  final num value;
  @override
  int get precedence => 10;
  @override
  String minimal() => '$value';
  @override
  String full() => '$value';
}

class _Neg extends _Node {
  _Neg(this.child);
  final _Node child;
  @override
  num get value => -child.value;
  @override
  int get precedence => 3;
  @override
  String minimal() =>
      '-${child.precedence >= 3 && child is! _Neg ? child.minimal() : '(${child.minimal()})'}';
  @override
  String full() => '(-${child.full()})';
}

class _Bin extends _Node {
  _Bin(this.op, this.left, this.right);
  final String op;
  final _Node left;
  final _Node right;

  @override
  num get value => switch (op) {
        '+' => left.value + right.value,
        '-' => left.value - right.value,
        '*' => left.value * right.value,
        '/' => left.value / right.value,
        '%' => left.value % right.value,
        '^' => math.pow(left.value, right.value),
        _ => throw StateError(op),
      };

  @override
  int get precedence => switch (op) {
        '+' || '-' => 1,
        '*' || '/' || '%' => 2,
        _ => 4, // ^
      };

  @override
  String minimal() {
    final p = precedence;
    // Left-associative operators need parens on the right at equal precedence;
    // ^ is right-associative, so the reverse applies.
    final rightAssoc = op == '^';
    final l = (rightAssoc ? left.precedence <= p : left.precedence < p)
        ? '(${left.minimal()})'
        : left.minimal();
    final r = (rightAssoc ? right.precedence < p : right.precedence <= p)
        ? '(${right.minimal()})'
        : right.minimal();
    return '$l $op $r';
  }

  @override
  String full() => '(${left.full()} $op ${right.full()})';
}

_Node _randomTree(math.Random rnd, int depth) {
  if (depth == 0 || rnd.nextInt(4) == 0) {
    return _Lit(rnd.nextBool()
        ? rnd.nextInt(20)
        : (rnd.nextInt(400) / 8)); // exact binary fractions like 3.125
  }
  switch (rnd.nextInt(8)) {
    case 0:
      return _Neg(_randomTree(rnd, depth - 1));
    case 1:
      // Keep powers small: non-negative base, small integer exponent.
      return _Bin('^', _Lit(rnd.nextInt(6)), _Lit(rnd.nextInt(4)));
    default:
      const ops = ['+', '-', '*', '/', '%'];
      return _Bin(ops[rnd.nextInt(ops.length)], _randomTree(rnd, depth - 1),
          _randomTree(rnd, depth - 1));
  }
}

/// A tree is usable when every sub-expression is finite, small enough that
/// integer arithmetic cannot overflow, and never divides by zero.
bool _isValid(_Node n) {
  try {
    final v = n.value;
    if (!v.isFinite || v.abs() > 1e15) return false;
    return switch (n) {
      _Lit() => true,
      _Neg(:final child) => _isValid(child),
      _Bin(:final op, :final left, :final right) => _isValid(left) &&
          _isValid(right) &&
          !((op == '/' || op == '%') && right.value == 0),
    };
  } catch (_) {
    return false; // integer division by zero etc.
  }
}

void main() {
  final engine = ExpressionEngine();

  test('random arithmetic matches Dart (minimal parentheses)', () {
    final rnd = math.Random(20260924);
    var checked = 0;
    while (checked < 2000) {
      final tree = _randomTree(rnd, 5);
      if (!_isValid(tree)) continue;
      final source = tree.minimal();
      final actual = engine.compile(source).evaluate();
      expect(actual, tree.value, reason: source);
      checked++;
    }
  });

  test('minimal and fully parenthesised forms agree', () {
    final rnd = math.Random(7);
    var checked = 0;
    while (checked < 1000) {
      final tree = _randomTree(rnd, 6);
      if (!_isValid(tree)) continue;
      expect(engine.compile(tree.minimal()).evaluate(),
          engine.compile(tree.full()).evaluate(),
          reason: '${tree.minimal()}  vs  ${tree.full()}');
      checked++;
    }
  });

  test('division by zero anywhere is an EvalError, never an exception leak',
      () {
    final rnd = math.Random(99);
    var checked = 0;
    while (checked < 300) {
      final tree = _Bin('/', _randomTree(rnd, 3), _Lit(0));
      final source = tree.minimal();
      Object? error;
      try {
        engine.compile(source).evaluate();
      } catch (e) {
        error = e;
      }
      expect(error, isA<EvalError>(), reason: source);
      checked++;
    }
  });

  test('the parser never throws anything but ParseError on random input', () {
    final rnd = math.Random(3);
    const alphabet = r'0123456789.+-*/%^()[],?:!=<>&|"$ abn{}';
    for (var i = 0; i < 3000; i++) {
      final len = rnd.nextInt(20);
      final source = String.fromCharCodes(List.generate(
          len, (_) => alphabet.codeUnitAt(rnd.nextInt(alphabet.length))));
      try {
        engine.compile(source).evaluate();
      } on ParseError {
        // expected for most random input
      } on EvalError {
        // e.g. type mismatch
      }
    }
  });
}
