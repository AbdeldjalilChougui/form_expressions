import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

void main() {
  // A fixed clock keeps date tests deterministic.
  final engine = ExpressionEngine(clock: () => DateTime(2026, 9, 24, 15, 30));
  Object? eval(String source, [Map<String, Object?> vars = const {}]) =>
      engine.compile(source).evaluate(variables: vars);

  Matcher evalError(Pattern message) => throwsA(
      isA<EvalError>().having((e) => e.message, 'message', contains(message)));

  group('maths', () {
    test('sum', () {
      expect(eval('sum(1, 2, 3)'), 6);
      expect(eval('sum()'), 0);
      expect(
          eval('sum(xs)', {
            'xs': [1, 2.5, null]
          }),
          3.5);
      expect(eval('sum(a, b)', {'a': 1}), 1);
    });
    test('min / max', () {
      expect(eval('min(5, 3, 8)'), 3);
      expect(eval('max(5, 3, 8)'), 8);
      expect(
          eval('max(xs)', {
            'xs': [4, 9, 2]
          }),
          9);
      expect(eval('min()'), isNull);
    });
    test('avg', () {
      expect(eval('avg(1, 2, 3, 4)'), 2.5);
      expect(eval('avg(xs)', {'xs': <Object?>[]}), isNull);
    });
    test('aggregate of a non-number is a type error', () {
      expect(() => eval('sum(1, "x")'), evalError('sum'));
    });
    test('abs', () {
      expect(eval('abs(-7)'), 7);
      expect(eval('abs(2.5)'), 2.5);
    });
    test('round', () {
      expect(eval('round(3.7)'), 4);
      expect(eval('round(3.7)'), isA<int>());
      expect(eval('round(-2.5)'), -3);
      expect(eval('round(3.567, 2)'), 3.57);
      expect(eval('round(1.005, 2)'), 1.01);
      expect(eval('round(1234, -2)'), 1200);
      expect(eval('round(0.1 + 0.2, 1)'), 0.3);
    });
    test('round rejects a fractional digit count', () {
      expect(() => eval('round(1, 1.5)'), evalError('integer'));
    });
    test('floor / ceil', () {
      expect(eval('floor(2.7)'), 2);
      expect(eval('floor(-2.1)'), -3);
      expect(eval('ceil(2.1)'), 3);
      expect(eval('ceil(5)'), 5);
    });
  });

  group('general', () {
    test('len', () {
      expect(eval('len("hello")'), 5);
      expect(
          eval('len(xs)', {
            'xs': [1, 2]
          }),
          2);
      expect(eval('len(x)'), 0);
      expect(() => eval('len(5)'), evalError('len'));
    });
    test('count counts non-empty values', () {
      expect(
          eval('count(xs)', {
            'xs': ['a', '', null, 'b']
          }),
          2);
      expect(eval('count(a, b, c)', {'a': 1, 'c': 'x'}), 2);
    });
    test('contains', () {
      expect(
          eval('contains(xs, "b")', {
            'xs': ['a', 'b']
          }),
          true);
      expect(eval('contains("hello", "lo")'), true);
      expect(eval('contains(x, "a")'), false);
    });
    test('isEmpty (case-insensitive name)', () {
      expect(eval('isEmpty(x)'), true);
      expect(eval('isEmpty("  ")'), true);
      expect(eval('isEmpty([])'), true);
      expect(eval('ISEMPTY("a")'), false);
      expect(eval('isempty(0)'), false);
    });
    test('number converts text input', () {
      expect(eval('number("12.5") * 2'), 25.0);
      expect(eval('number(" 7 ")'), 7);
      expect(eval('number(x)'), isNull);
      expect(() => eval('number("abc")'), evalError('number'));
    });
    test('string formats any value', () {
      expect(eval('string(6 / 2)'), '3');
      expect(eval('string(null)'), '');
    });
  });

  group('strings', () {
    test('upper / lower / trim', () {
      expect(eval('upper("abc")'), 'ABC');
      expect(eval('lower("ABC")'), 'abc');
      expect(eval('trim("  x ")'), 'x');
      expect(eval('upper(x)'), isNull);
      expect(() => eval('upper(1)'), evalError('upper'));
    });
    test('concat', () {
      expect(eval('concat("a", 1, null, true)'), 'a1true');
      expect(eval('concat()'), '');
    });
  });

  group('dates', () {
    test('today is midnight of the clock date', () {
      expect(eval('today()'), DateTime(2026, 9, 24));
    });
    test('date parses ISO strings', () {
      expect(eval('date("2020-02-29")'), DateTime(2020, 2, 29));
      expect(eval('date(x)'), isNull);
      expect(() => eval('date("not a date")'), evalError('date'));
    });
    test('age in whole years', () {
      expect(eval('age("2000-09-24")'), 26);
      expect(eval('age("2000-09-25")'), 25);
      expect(eval('age(dob)', {'dob': DateTime(1990, 1, 1)}), 36);
      expect(eval('age(x)'), isNull);
    });
    test('dateDiff defaults to days', () {
      expect(eval('dateDiff("2026-01-01", "2026-03-01")'), 59);
      expect(eval('dateDiff("2026-03-01", "2026-01-01")'), -59);
    });
    test('dateDiff ignores DST and time of day', () {
      expect(
          eval('dateDiff(a, b)', {
            'a': DateTime(2026, 3, 28, 23, 0),
            'b': DateTime(2026, 3, 30, 1, 0),
          }),
          2);
    });
    test('dateDiff units', () {
      expect(eval('dateDiff("2026-01-01", "2026-01-20", "weeks")'), 2);
      expect(eval('dateDiff("2026-01-31", "2026-03-30", "months")'), 1);
      expect(eval('dateDiff("2026-01-31", "2026-03-31", "months")'), 2);
      expect(eval('dateDiff("2026-03-31", "2026-01-31", "months")'), -2);
      expect(eval('dateDiff("2000-06-15", "2026-06-14", "years")'), 25);
      expect(
          () => eval('dateDiff(today(), today(), "hours")'), evalError('unit'));
    });
    test('addDays', () {
      expect(eval('addDays("2026-02-27", 2)'), DateTime(2026, 3, 1));
      expect(eval('addDays(today(), -1) < today()'), true);
    });
    test('a date function with a number argument is a type error', () {
      expect(() => eval('age(5)'), evalError('age'));
    });
  });

  group('custom functions', () {
    test('register and call', () {
      final e = ExpressionEngine()
        ..register('vat', (args) => (args[0]! as num) * 1.2,
            minArgs: 1, maxArgs: 1);
      expect(e.compile('vat(100)').evaluate(), 120);
      expect(e.compile('VAT(10)').functions, {'vat'});
    });
    test('arity is checked at compile time', () {
      final e = ExpressionEngine()..register('two', (a) => 2, maxArgs: 0);
      expect(() => e.compile('two(1)'), throwsA(isA<ParseError>()));
    });
    test('errors thrown by custom code become EvalErrors', () {
      final e = ExpressionEngine()
        ..register('boom', (a) => throw StateError('bad'));
      expect(
        () => e.compile('1 + boom()').evaluate(),
        throwsA(isA<EvalError>()
            .having((x) => x.offset, 'offset', 4)
            .having((x) => x.message, 'message', contains('boom'))),
      );
    });
    test('unsupported return values are rejected', () {
      final e = ExpressionEngine()..register('obj', (a) => Object());
      expect(() => e.compile('obj()').evaluate(), throwsA(isA<EvalError>()));
    });
    test('built-ins cannot be replaced by accident', () {
      final e = ExpressionEngine();
      expect(() => e.register('sum', (a) => 0), throwsArgumentError);
      e.register('sum', (a) => 42, replace: true);
      expect(e.compile('sum(1)').evaluate(), 42);
    });
    test('if and invalid names are reserved', () {
      final e = ExpressionEngine();
      expect(() => e.register('if', (a) => 0), throwsArgumentError);
      expect(() => e.register('and', (a) => 0), throwsArgumentError);
      expect(() => e.register('1x', (a) => 0), throwsArgumentError);
    });
    test('engines are isolated from each other', () {
      ExpressionEngine().register('only_here', (a) => 1);
      expect(() => ExpressionEngine().compile('only_here()'),
          throwsA(isA<ParseError>()));
    });
    test('functionNames lists built-ins', () {
      expect(engine.functionNames, containsAll(['sum', 'isempty', 'datediff']));
    });
  });
}
