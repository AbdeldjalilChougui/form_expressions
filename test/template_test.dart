import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

void main() {
  final engine = ExpressionEngine(clock: () => DateTime(2026, 9, 24));
  String render(String source, [Map<String, Object?> vars = const {}]) =>
      engine.template(source).render(variables: vars);

  group('substitution', () {
    test('plain field', () {
      expect(render('Hello {{name}}!', {'name': 'Alice'}), 'Hello Alice!');
    });
    test('whitespace inside braces is ignored', () {
      expect(render('{{  name  }}', {'name': 'A'}), 'A');
    });
    test('several fields', () {
      expect(render('{{first}} {{last}}', {'first': 'Amir', 'last': 'Benali'}),
          'Amir Benali');
    });
    test('text without placeholders is returned unchanged', () {
      expect(render('No fields here { }'), 'No fields here { }');
    });
    test('empty template', () => expect(render(''), ''));
    test('dotted paths and \$ variables', () {
      expect(
          render(r'{{address.city}} / {{$address.zip}}', {
            'address': {'city': 'Oran', 'zip': 31000},
          }),
          'Oran / 31000');
    });
  });

  group('value formatting', () {
    test('null renders as empty', () {
      expect(render('Hi {{name}}', {'name': null}), 'Hi ');
      expect(render('Hi {{name}}'), 'Hi ');
    });
    test('lists are comma separated', () {
      expect(
          render('Items: {{items}}', {
            'items': ['A', 'B', 'C']
          }),
          'Items: A, B, C');
    });
    test('integral doubles print without a trailing .0', () {
      expect(render('{{6 / 2}} {{7 / 2}}'), '3 3.5');
    });
    test('dates print as ISO dates', () {
      expect(render('{{today()}}'), '2026-09-24');
      expect(render('{{d}}', {'d': DateTime(2026, 1, 2, 3, 4, 5)}),
          '2026-01-02T03:04:05.000');
    });
    test('booleans', () => expect(render('{{1 < 2}}'), 'true'));
  });

  group('expressions and filters', () {
    test('arbitrary expressions', () {
      expect(render('Total: {{price * qty}}', {'price': 4, 'qty': 3}),
          'Total: 12');
    });
    test('single filter', () {
      expect(render('{{name | upper}}', {'name': 'ann'}), 'ANN');
    });
    test('chained filters', () {
      expect(render('{{name | trim | upper}}', {'name': '  ann '}), 'ANN');
    });
    test('filter with arguments receives the value first', () {
      expect(render('{{ratio | round(2)}}', {'ratio': 0.12345}), '0.12');
    });
    test('custom functions work as filters', () {
      final e = ExpressionEngine()
        ..register('currency', (a) => '${a[1]}${a[0]}', minArgs: 2);
      expect(
          e.template(r'{{total | currency("$")}}').render(variables: {
            'total': 5,
          }),
          r'$5');
    });
    test('|| inside a template is still logical or', () {
      expect(render('{{a || b}}', {'a': false, 'b': true}), 'true');
    });
    test('strings containing braces do not end the placeholder', () {
      expect(render('{{ "}}" + x }}', {'x': '!'}), '}}!');
    });
  });

  group('missing-value fallback', () {
    test('?? supplies a default', () {
      expect(render('Hello {{name ?? "friend"}}'), 'Hello friend');
      expect(
          render('Hello {{name ?? "friend"}}', {'name': 'Sara'}), 'Hello Sara');
    });
    test('fallback combined with a filter', () {
      expect(render('{{name ?? "friend" | upper}}'), 'FRIEND');
    });
  });

  group('escaping', () {
    test(r'\{{ renders literal braces', () {
      expect(render(r'Use \{{name}} to insert', {'name': 'x'}),
          'Use {{name}} to insert');
    });
    test('other backslashes are kept', () {
      expect(render(r'C:\path {{a}}', {'a': 1}), r'C:\path 1');
    });
    test('lone closing braces are literal', () {
      expect(render('a }} b'), 'a }} b');
    });
  });

  group('errors', () {
    test('unterminated placeholder is a ParseError at the opening braces', () {
      expect(
        () => engine.template('Hi {{name'),
        throwsA(isA<ParseError>()
            .having((e) => e.offset, 'offset', 3)
            .having((e) => e.message, 'message', contains("'}}'"))),
      );
    });
    test('empty placeholder', () {
      expect(() => engine.template('a {{ }} b'),
          throwsA(isA<ParseError>().having((e) => e.offset, 'offset', 5)));
    });
    test('parse error positions are relative to the whole template', () {
      expect(
        () => engine.template('Hello {{ 1 + }}'),
        throwsA(isA<ParseError>().having((e) => e.offset, 'offset', 13)),
      );
    });
    test('unknown filter', () {
      expect(
        () => engine.template('{{ x | shout }}'),
        throwsA(isA<ParseError>()
            .having((e) => e.offset, 'offset', 7)
            .having((e) => e.message, 'message', contains('shout'))),
      );
    });
    test('eval errors carry the template position', () {
      expect(
        () => render('Ratio {{a / b}}', {'a': 1, 'b': 0}),
        throwsA(isA<EvalError>()
            .having((e) => e.offset, 'offset', 10)
            .having((e) => e.source, 'source', 'Ratio {{a / b}}')),
      );
    });
    test('onError lets the host substitute text', () {
      final out = engine.template('R={{a / b}};').render(
        variables: {'a': 1, 'b': 0},
        onError: (e) => '#ERR',
      );
      expect(out, 'R=#ERR;');
    });
  });

  group('analysis', () {
    test('variables across all placeholders', () {
      expect(engine.template('{{a}} {{b.c | upper}} {{d ?? e}}').variables,
          {'a', 'b.c', 'd', 'e'});
    });
  });
}
