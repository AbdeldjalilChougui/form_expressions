import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

void main() {
  final engine = ExpressionEngine();
  Object? eval(String source, [Map<String, Object?> vars = const {}]) =>
      engine.compile(source).evaluate(variables: vars);

  Matcher evalErrorAt(int offset, Pattern message) => throwsA(isA<EvalError>()
      .having((e) => e.offset, 'offset', offset)
      .having((e) => e.message, 'message', contains(message)));

  group('literals and types', () {
    test('numbers', () {
      expect(eval('42'), 42);
      expect(eval('42'), isA<int>());
      expect(eval('2.5'), 2.5);
    });
    test('strings', () => expect(eval('"hi"'), 'hi'));
    test('booleans and null', () {
      expect(eval('true'), true);
      expect(eval('false'), false);
      expect(eval('null'), isNull);
    });
    test(
        'lists',
        () => expect(eval('[1, "a", [true]]'), [
              1,
              'a',
              [true]
            ]));
    test('empty list', () => expect(eval('[]'), <Object?>[]));
  });

  group('arithmetic', () {
    test('precedence', () => expect(eval('1 + 2 * 3'), 7));
    test('left associativity', () {
      expect(eval('10 - 4 - 3'), 3);
      expect(eval('64 / 4 / 2'), 8);
    });
    test('power is right-associative', () => expect(eval('2 ^ 3 ^ 2'), 512));
    test('unary minus binds looser than power', () {
      expect(eval('-2 ^ 2'), -4);
      expect(eval('(-2) ^ 2'), 4);
      expect(eval('2 ^ -1'), 0.5);
    });
    test('int arithmetic stays int', () {
      expect(eval('3 * 4 - 2'), isA<int>());
      expect(eval('2 ^ 10'), 1024);
      expect(eval('2 ^ 10'), isA<int>());
    });
    test('division always yields a double', () {
      expect(eval('10 / 4'), 2.5);
      expect(eval('6 / 2'), 3.0);
    });
    test('modulo uses Euclidean remainder', () {
      expect(eval('10 % 3'), 1);
      expect(eval('-7 % 3'), 2);
      expect(eval('5.5 % 2'), 1.5);
    });
    test('unary plus and minus', () {
      expect(eval('-5 + 10'), 5);
      expect(eval('+5'), 5);
      expect(eval('--5'), 5);
    });
    test('large int products fall back to double instead of wrapping', () {
      final r = eval('9007199254740993 * 1000') as num;
      expect(r, isA<double>());
      expect(r, greaterThan(9e18));
    });
    test('division by zero is an EvalError at the operator', () {
      expect(() => eval('5 / 0'), evalErrorAt(2, 'Division by zero'));
      expect(() => eval('5 % (1 - 1)'), evalErrorAt(2, 'Division by zero'));
    });
    test('overflow to infinity is an EvalError', () {
      expect(() => eval('10 ^ 400'), evalErrorAt(3, 'finite'));
      expect(() => eval('1e308 * 10'), evalErrorAt(6, 'finite'));
    });
    test('NaN results are an EvalError', () {
      expect(() => eval('(-8) ^ 0.5'), evalErrorAt(5, 'finite'));
    });
  });

  group('type mismatches give clear errors', () {
    test('number minus string', () {
      expect(() => eval('1 - "a"'),
          evalErrorAt(2, "Cannot apply '-' to number and string"));
    });
    test('null in arithmetic hints at ??', () {
      expect(() => eval(r'$a * 2'), evalErrorAt(3, '??'));
    });
    test('negating a string', () {
      expect(() => eval('-"a"'), evalErrorAt(0, "Cannot apply '-' to string"));
    });
    test('ordering a number and a string', () {
      expect(() => eval('1 < "2"'),
          evalErrorAt(2, 'Cannot compare number and string'));
    });
    test('non-boolean condition', () {
      expect(() => eval('1 and true'), evalErrorAt(0, 'Expected a bool'));
      expect(() => eval('"x" ? 1 : 2'), evalErrorAt(0, 'Expected a bool'));
      expect(() => eval('not 3'), evalErrorAt(4, 'Expected a bool'));
    });
    test('indexing a number', () {
      expect(() => eval('5[0]'), evalErrorAt(0, 'Cannot index'));
    });
  });

  group('string concatenation', () {
    test('string + string', () => expect(eval('"ab" + "cd"'), 'abcd'));
    test('string + number formats the number', () {
      expect(eval('"n=" + 3'), 'n=3');
      expect(eval('"n=" + 6 / 2'), 'n=3');
      expect(eval('1 + 2 + "x"'), '3x');
    });
    test('string + null renders null as empty',
        () => expect(eval(r'"Hi " + $name'), 'Hi '));
  });

  group('comparison and equality', () {
    test('numbers', () {
      expect(eval('2 < 3'), true);
      expect(eval('3 <= 3'), true);
      expect(eval('2 > 3'), false);
      expect(eval('3 >= 4'), false);
      expect(eval('1 == 1.0'), true);
      expect(eval('1 != 2'), true);
    });
    test('strings compare lexicographically', () {
      expect(eval('"apple" < "banana"'), true);
      expect(eval('"a" == "a"'), true);
    });
    test('mixed types are unequal but not an error', () {
      expect(eval('1 == "1"'), false);
      expect(eval('null == 0'), false);
      expect(eval('null == null'), true);
    });
    test('lists compare deeply', () {
      expect(eval('[1, [2]] == [1, [2.0]]'), true);
      expect(eval('[1] != [2]'), true);
    });
    test('ordering with null is false, never a crash', () {
      expect(eval(r'$age > 18'), false);
      expect(eval(r'$age <= 18'), false);
    });
    test('dates', () {
      final vars = {
        'a': DateTime(2020, 1, 1),
        'b': DateTime(2021, 1, 1),
        'c': DateTime(2020, 1, 1),
      };
      expect(eval('a < b', vars), true);
      expect(eval('a == c', vars), true);
      expect(eval('b >= a', vars), true);
    });
  });

  group('logic', () {
    test('word and symbol forms', () {
      expect(eval('true and false'), false);
      expect(eval('true && true'), true);
      expect(eval('false or true'), true);
      expect(eval('false || false'), false);
      expect(eval('not false'), true);
      expect(eval('!true'), false);
    });
    test('null counts as false in conditions', () {
      expect(eval(r'$missing or true'), true);
      expect(eval(r'not $missing'), true);
      expect(eval(r'$missing ? 1 : 2'), 2);
    });
    test('and/or short-circuit', () {
      expect(eval('false and 1 / 0 > 1'), false);
      expect(eval('true or 1 / 0 > 1'), true);
    });
    test('ternary evaluates only the chosen branch', () {
      expect(eval('true ? 1 : 1 / 0'), 1);
      expect(eval('1 > 2 ? "a" : 1 > 0 ? "b" : "c"'), 'b');
    });
    test('if() is lazy and allows a missing else', () {
      expect(eval('if(false, 1 / 0, 7)'), 7);
      expect(eval('if(false, 1)'), isNull);
    });
    test('?? returns the fallback only for null', () {
      expect(eval(r'$x ?? 5'), 5);
      expect(eval(r'$x ?? 5', {'x': 0}), 0);
      expect(eval(r'$x ?? $y ?? "z"'), 'z');
      expect(eval('1 ?? 1 / 0'), 1);
    });
  });

  group('in operator', () {
    test('list membership', () {
      expect(eval('2 in [1, 2, 3]'), true);
      expect(eval('"b" in ["a"]'), false);
      expect(eval('2.0 in [1, 2]'), true);
    });
    test('substring', () => expect(eval('"ell" in "hello"'), true));
    test('not in', () => expect(eval('4 not in [1, 2]'), true));
    test('null container is false', () {
      expect(eval(r'"a" in $choices'), false);
    });
    test('bad container', () {
      expect(() => eval('1 in 5'), evalErrorAt(2, "'in'"));
    });
  });

  group('variables', () {
    test(r'$name and bare identifiers are equivalent', () {
      expect(eval(r'$x + y', {'x': 3, 'y': 4}), 7);
    });
    test('braced names allow any characters', () {
      expect(eval(r'${first-name} + "!"', {'first-name': 'Ann'}), 'Ann!');
    });
    test('dotted paths walk nested maps and lists', () {
      final vars = {
        'address': {'city': 'Oran'},
        'items': [
          {'price': 5},
          {'price': 7},
        ],
      };
      expect(eval('address.city', vars), 'Oran');
      expect(eval(r'$items.1.price', vars), 7);
      expect(eval('address.zip', vars), isNull);
    });
    test('a flat key containing a dot wins over nesting', () {
      expect(
          eval('a.b', {
            'a.b': 1,
            'a': {'b': 2}
          }),
          1);
    });
    test('list indexing', () {
      expect(
          eval('xs[1]', {
            'xs': [10, 20]
          }),
          20);
      expect(
          eval('xs[5]', {
            'xs': [10, 20]
          }),
          isNull);
      expect(eval('"abc"[0]'), 'a');
    });
    test('non-ASCII field names work as bare identifiers', () {
      expect(eval('العمر + 1', {'العمر': 30}), 31);
    });
    test('keywords are case-insensitive', () {
      expect(eval('TRUE And NOT False'), true);
    });
    test('custom resolver receives the full dotted path', () {
      final seen = <String>[];
      final expr = engine.compile(r'$a.b + c');
      final result = expr.evaluate(resolver: (path) {
        seen.add(path);
        return 1;
      });
      expect(result, 2);
      expect(seen, ['a.b', 'c']);
    });
    test('iterables are converted to lists', () {
      expect(
          eval('len(xs)', {
            'xs': {1, 2, 3}
          }),
          3);
    });
    test('unsupported host values are an EvalError, not a crash', () {
      expect(() => eval(r'1 + $o', {'o': Object()}),
          evalErrorAt(4, 'unsupported type'));
    });
  });

  group('typed helpers', () {
    test('evaluateBool', () {
      expect(engine.compile('1 < 2').evaluateBool(), true);
      expect(engine.compile(r'$x').evaluateBool(), false);
      expect(
          () => engine.compile('1').evaluateBool(), throwsA(isA<EvalError>()));
    });
    test('evaluateNum', () {
      expect(engine.compile('1 + 1').evaluateNum(), 2);
      expect(
          () => engine.compile('"a"').evaluateNum(), throwsA(isA<EvalError>()));
      expect(
          () => engine.compile(r'$x').evaluateNum(), throwsA(isA<EvalError>()));
    });
  });

  group('compile once, evaluate many', () {
    test('the same Expression gives fresh results per scope', () {
      final expr = engine.compile('price * qty');
      expect(expr.evaluate(variables: {'price': 2, 'qty': 3}), 6);
      expect(expr.evaluate(variables: {'price': 5, 'qty': 5}), 25);
      expect(expr.source, 'price * qty');
    });
    test('engine.evaluate is a one-shot shortcut', () {
      expect(engine.evaluate('a + 1', variables: {'a': 1}), 2);
    });
  });

  group('eval error formatting', () {
    test('toString contains position and caret', () {
      try {
        eval('1 + 2 / 0');
        fail('should throw');
      } on EvalError catch (e) {
        expect(e.line, 1);
        expect(e.column, 7);
        expect(e.source, '1 + 2 / 0');
        expect(e.toString(), contains('Division by zero'));
        expect(e.toString(), contains('      ^'));
      }
    });
  });
}
