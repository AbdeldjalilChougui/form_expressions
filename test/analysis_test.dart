import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

void main() {
  final engine = ExpressionEngine();

  group('static analysis', () {
    test('lists referenced variables as dotted paths', () {
      final e = engine.compile(r'$price * qty + address.zip + ${a-b} + sum(x)');
      expect(e.variables, {'price', 'qty', 'address.zip', 'a-b', 'x'});
    });
    test('finds variables in every branch, even ones not evaluated', () {
      final e = engine.compile('flag ? left : if(other, [inner], fallback)');
      expect(e.variables, {'flag', 'left', 'other', 'inner', 'fallback'});
    });
    test('literals and keywords are not variables', () {
      expect(engine.compile('true and "x" in ["y"] or null == 1').variables,
          isEmpty);
    });
    test('lists referenced functions in lowercase', () {
      expect(engine.compile('SUM(1) + Max(2) + if(true, 1, 2)').functions,
          {'sum', 'max', 'if'});
    });
    test('variables are listed in source order', () {
      expect(engine.compile('c + max(a, b) * d').variables.toList(),
          ['c', 'a', 'b', 'd']);
    });
    test('index expressions contribute their variables', () {
      expect(engine.compile('xs[i + 1]').variables, {'xs', 'i'});
    });
  });

  group('orderCalculations', () {
    Map<String, Expression> calcs(Map<String, String> sources) =>
        sources.map((k, v) => MapEntry(k, engine.compile(v)));

    test('orders fields so dependencies come first', () {
      final order = orderCalculations(calcs({
        'total': 'subtotal + tax',
        'tax': 'subtotal * 0.2',
        'subtotal': 'price * qty',
      }));
      expect(order.order, ['subtotal', 'tax', 'total']);
      expect(order.hasCycles, isFalse);
      expect(order.cycles, isEmpty);
      expect(order.blocked, isEmpty);
    });

    test('keeps declaration order among independent fields', () {
      final order = orderCalculations(calcs({'b': '1', 'a': '2', 'c': 'b'}));
      expect(order.order, ['b', 'a', 'c']);
    });

    test('dotted references count as a dependency on the root name', () {
      final order = orderCalculations(calcs({
        'summary': 'address.city',
        'address': 'x',
      }));
      expect(order.order, ['address', 'summary']);
    });

    test('reports a two-node cycle and blocks its dependents', () {
      final order = orderCalculations(calcs({
        'a': 'b + 1',
        'b': 'a + 1',
        'c': 'a * 2',
        'd': '5',
      }));
      expect(order.hasCycles, isTrue);
      expect(order.cycles, [
        ['a', 'b'],
      ]);
      expect(order.blocked, {'c'});
      expect(order.order, ['d']);
    });

    test('reports a self-reference as a cycle', () {
      final order = orderCalculations(calcs({'x': 'x + 1'}));
      expect(order.cycles, [
        ['x'],
      ]);
      expect(order.order, isEmpty);
    });

    test('reports several independent cycles', () {
      final order = orderCalculations(calcs({
        'a': 'b',
        'b': 'c',
        'c': 'a',
        'p': 'q',
        'q': 'p',
        'ok': 'field',
      }));
      expect(order.cycles, [
        ['a', 'b', 'c'],
        ['p', 'q'],
      ]);
      expect(order.order, ['ok']);
    });

    test('generic orderDependencies works on plain names', () {
      final order = orderDependencies({
        'c': {'b'},
        'b': {'a'},
        'a': {'external'},
      });
      expect(order.order, ['a', 'b', 'c']);
    });

    test('toString describes each cycle', () {
      final order = orderCalculations(calcs({'a': 'b', 'b': 'a'}));
      expect(order.toString(), contains('a -> b -> a'));
    });
  });

  group('evaluateCalculations', () {
    test('evaluates in dependency order, layering results', () {
      final result = evaluateCalculations(
        {
          'total': engine.compile('subtotal * 1.2'),
          'subtotal': engine.compile('price * qty'),
        },
        variables: {'price': 5, 'qty': 2},
      );
      expect(result.values, {'subtotal': 10, 'total': 12.0});
      expect(result.errors, isEmpty);
    });

    test('an error in one field is captured and dependents see null', () {
      final result = evaluateCalculations(
        {
          'ratio': engine.compile('a / b'),
          'label': engine.compile('ratio ?? "n/a"'),
        },
        variables: {'a': 1, 'b': 0},
      );
      expect(result.errors.keys, ['ratio']);
      expect(result.values['ratio'], isNull);
      expect(result.values['label'], 'n/a');
    });

    test('cyclic fields are skipped, not evaluated', () {
      final result = evaluateCalculations({
        'a': engine.compile('b'),
        'b': engine.compile('a'),
        'c': engine.compile('1'),
      });
      expect(result.values, {'c': 1});
      expect(result.order.hasCycles, isTrue);
    });

    test('works with a custom resolver', () {
      final result = evaluateCalculations(
        {'double': engine.compile('n * 2')},
        resolver: (path) => path == 'n' ? 21 : null,
      );
      expect(result.values['double'], 42);
    });
  });
}
