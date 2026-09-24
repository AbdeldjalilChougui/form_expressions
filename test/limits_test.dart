import 'package:form_expressions/form_expressions.dart';
import 'package:test/test.dart';

void main() {
  group('limits', () {
    test('defaults are sensible', () {
      const l = ExpressionLimits();
      expect(l.maxLength, 4096);
      expect(l.maxDepth, 64);
      expect(l.maxTemplateLength, 65536);
    });

    test('expressions longer than maxLength are rejected before lexing', () {
      final engine =
          ExpressionEngine(limits: const ExpressionLimits(maxLength: 10));
      expect(engine.compile('1 + 2 + 3').evaluate(), 6);
      expect(
        () => engine.compile('1 + 2 + 3 + 4'),
        throwsA(isA<ParseError>()
            .having((e) => e.offset, 'offset', 10)
            .having((e) => e.message, 'message', contains('too long'))),
      );
    });

    test('deep parenthesis nesting is rejected', () {
      final engine =
          ExpressionEngine(limits: const ExpressionLimits(maxDepth: 20));
      expect(engine.compile('${'(' * 10}1${')' * 10}').evaluate(), 1);
      expect(
        () => engine.compile('${'(' * 50}1${')' * 50}'),
        throwsA(isA<ParseError>().having(
            (e) => e.message, 'message', contains('nested too deeply'))),
      );
    });

    test('long unary chains are rejected', () {
      final engine =
          ExpressionEngine(limits: const ExpressionLimits(maxDepth: 20));
      expect(() => engine.compile('${'-' * 100}1'), throwsA(isA<ParseError>()));
      expect(() => engine.compile('${'not ' * 100}true'),
          throwsA(isA<ParseError>()));
    });

    test('deep power towers and ternaries are rejected', () {
      final engine =
          ExpressionEngine(limits: const ExpressionLimits(maxDepth: 20));
      expect(() => engine.compile(List.filled(100, '2').join('^')),
          throwsA(isA<ParseError>()));
      expect(() => engine.compile('${'a ? b : ' * 100}c'),
          throwsA(isA<ParseError>()));
      expect(() => engine.compile('${'f(' * 100}${')' * 100}'),
          throwsA(isA<ParseError>()));
    });

    test('long flat expressions within the length limit are fine', () {
      final engine = ExpressionEngine();
      final source = List.filled(1000, '1').join('+');
      expect(engine.compile(source).evaluate(), 1000);
    });

    test('pathologically deep input is a ParseError, never a StackOverflow',
        () {
      final engine = ExpressionEngine(
          limits: const ExpressionLimits(maxLength: 1000000, maxDepth: 64));
      expect(
          () => engine.compile('${'(' * 100000}1'), throwsA(isA<ParseError>()));
      expect(
          () => engine.compile('${'[' * 100000}1'), throwsA(isA<ParseError>()));
    });

    test('templates longer than maxTemplateLength are rejected', () {
      final engine = ExpressionEngine(
          limits: const ExpressionLimits(maxTemplateLength: 20));
      expect(() => engine.template('x' * 21), throwsA(isA<ParseError>()));
      expect(engine.template('x' * 20).render(), 'x' * 20);
    });

    test('deeply nested host data is rejected, not recursed forever', () {
      final engine =
          ExpressionEngine(limits: const ExpressionLimits(maxDepth: 10));
      Object? nested = 1;
      for (var i = 0; i < 50; i++) {
        nested = [nested];
      }
      expect(() => engine.compile('len(x)').evaluate(variables: {'x': nested}),
          throwsA(isA<EvalError>()));
    });

    test('self-referencing host lists do not hang', () {
      final engine = ExpressionEngine();
      final list = <Object?>[1];
      list.add(list);
      expect(() => engine.compile('sum(x)').evaluate(variables: {'x': list}),
          throwsA(isA<EvalError>()));
    });

    test('invalid limits are rejected', () {
      expect(
          () => ExpressionEngine(limits: const ExpressionLimits(maxDepth: 0)),
          throwsArgumentError);
    });
  });

  group('sandbox', () {
    test('there is no way to reach Dart members or eval', () {
      final engine = ExpressionEngine();
      // Method-call syntax and member access on values are not in the grammar.
      expect(() => engine.compile('"a".toUpperCase()'),
          throwsA(isA<ParseError>()));
      expect(() => engine.compile('print("x")'), throwsA(isA<ParseError>()));
      // A path is only ever a lookup key handed to the resolver.
      expect(engine.compile('runtimeType.hashCode').evaluate(), isNull);
    });
  });
}
