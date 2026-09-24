import 'package:form_expressions/form_expressions.dart';
import 'package:form_expressions/src/lexer.dart';
import 'package:form_expressions/src/parser.dart';
import 'package:form_expressions/src/token.dart';
import 'package:test/test.dart';

/// Parses [source] and returns the canonical, fully parenthesised AST dump.
String ast(String source) => Parser.parseSource(
      source,
      limits: const ExpressionLimits(),
      functionArity: ExpressionEngine().arityOf,
    ).toString();

List<TokenType> types(String source) =>
    Lexer(source).tokenize().map((t) => t.type).toList();

void main() {
  group('Lexer', () {
    test('tokenises numbers, strings, identifiers and operators', () {
      expect(types('1 + 2.5 * "a"'), [
        TokenType.number,
        TokenType.plus,
        TokenType.number,
        TokenType.star,
        TokenType.string,
        TokenType.eof,
      ]);
    });

    test('recognises keywords', () {
      expect(types('true false null and or not in'), [
        TokenType.trueKw,
        TokenType.falseKw,
        TokenType.nullKw,
        TokenType.and,
        TokenType.or,
        TokenType.not,
        TokenType.inKw,
        TokenType.eof,
      ]);
    });

    test('recognises symbolic operators including two-character ones', () {
      expect(types('&& || ! == != <= >= < > ?? ? : ^ % /'), [
        TokenType.and,
        TokenType.or,
        TokenType.not,
        TokenType.eq,
        TokenType.neq,
        TokenType.lte,
        TokenType.gte,
        TokenType.lt,
        TokenType.gt,
        TokenType.nullish,
        TokenType.question,
        TokenType.colon,
        TokenType.caret,
        TokenType.percent,
        TokenType.slash,
        TokenType.eof,
      ]);
    });

    test('a dot after a value is a path separator, not a decimal', () {
      expect(types('a.5'), [
        TokenType.identifier,
        TokenType.dot,
        TokenType.number,
        TokenType.eof,
      ]);
    });

    test('records token offsets', () {
      final tokens = Lexer('  ab + 12').tokenize();
      expect(tokens.map((t) => t.offset), [2, 5, 7, 9]);
    });

    test(r'reads $name and ${braced name} variables', () {
      final tokens = Lexer(r'$age + ${first-name}').tokenize();
      expect(tokens[0].type, TokenType.variable);
      expect(tokens[0].lexeme, 'age');
      expect(tokens[2].type, TokenType.variable);
      expect(tokens[2].lexeme, 'first-name');
    });

    test('decodes string escapes', () {
      final t = Lexer(r'"a\"b\n\t\\ \u0041\u{1F600}" ' "'it\\'s'").tokenize();
      expect(t[0].value, 'a"b\n\t\\ A\u{1F600}');
      expect(t[1].value, "it's");
    });

    test('parses number forms', () {
      final values = Lexer('7 3.25 1e3 2.5E-1 + .5')
          .tokenize()
          .where((t) => t.type == TokenType.number)
          .map((t) => t.value)
          .toList();
      expect(values, [7, 3.25, 1000.0, 0.25, 0.5]);
      expect(values.first, isA<int>());
    });
  });

  group('Precedence table', () {
    // Each row: source -> canonical tree.
    const table = <String, String>{
      '1 + 2 * 3': '(+ 1 (* 2 3))',
      '1 * 2 + 3': '(+ (* 1 2) 3)',
      '1 - 2 - 3': '(- (- 1 2) 3)',
      '8 / 4 / 2': '(/ (/ 8 4) 2)',
      '7 % 3 * 2': '(* (% 7 3) 2)',
      '2 ^ 3 ^ 2': '(^ 2 (^ 3 2))',
      '-2 ^ 2': '(neg (^ 2 2))',
      '2 ^ -1': '(^ 2 (neg 1))',
      '2 * 3 ^ 2': '(* 2 (^ 3 2))',
      '--1': '(neg (neg 1))',
      '(1 + 2) * 3': '(* (+ 1 2) 3)',
      '1 + 2 < 4': '(< (+ 1 2) 4)',
      '1 < 2 == true': '(== (< 1 2) true)',
      'a == b != c': '(!= (== \$a \$b) \$c)',
      'a and b or c': '(or (and \$a \$b) \$c)',
      'a or b and c': '(or \$a (and \$b \$c))',
      'a || b && c': '(or \$a (and \$b \$c))',
      'not a and b': '(and (not \$a) \$b)',
      '!a || b': '(or (not \$a) \$b)',
      'not a == b': '(not (== \$a \$b))',
      'not not a': '(not (not \$a))',
      'a ? b : c ? d : e': '(? \$a \$b (? \$c \$d \$e))',
      'a or b ? 1 : 2': '(? (or \$a \$b) 1 2)',
      'a ?? b ?? c': '(?? (?? \$a \$b) \$c)',
      'a ?? b or c': '(?? \$a (or \$b \$c))',
      'x in [1, 2] and y': '(and (in \$x [1, 2]) \$y)',
      'x not in list': '(not-in \$x \$list)',
      '1 + 2 in xs': '(in (+ 1 2) \$xs)',
      'a.b.c + 1': '(+ \$a.b.c 1)',
      r'$a.b * 2': '(* \$a.b 2)',
      'items[0] + 1': '(+ (index \$items 0) 1)',
      'sum(1, 2 * 3) - max(a)': '(- sum(1, (* 2 3)) max(\$a))',
      '"x" + 1': '(+ "x" 1)',
      'if(a, 1, 2)': 'if(\$a, 1, 2)',
    };
    table.forEach((source, tree) {
      test('$source  =>  $tree', () => expect(ast(source), tree));
    });
  });

  group('Parse errors', () {
    Matcher parseErrorAt(int offset, Matcher message) => isA<ParseError>()
        .having((e) => e.offset, 'offset', offset)
        .having((e) => e.message, 'message', message);

    void expectError(String source, int offset, [Pattern? message]) {
      expect(
        () => ast(source),
        throwsA(parseErrorAt(
            offset, message == null ? anything : contains(message))),
      );
    }

    test('empty expression', () => expectError('   ', 3, 'Empty'));
    test('unexpected character', () => expectError('1 + #', 4, "'#'"));
    test('unterminated string points at the quote',
        () => expectError('1 + "abc', 4, 'Unterminated string'));
    test('bad escape', () => expectError(r'"a\q"', 2, 'escape'));
    test('missing closing paren',
        () => expectError('(1 + 2', 6, "Expected ')'"));
    test('trailing token', () => expectError('1 2', 2, "Unexpected '2'"));
    test('dangling operator', () => expectError('1 +', 3, 'end of expression'));
    test('single = suggests ==', () => expectError('a = 1', 2, "'=='"));
    test('single & suggests &&', () => expectError('a & b', 2, "'&&'"));
    test('single | outside a template', () => expectError('a | b', 2, "'||'"));
    test('chained comparison is rejected',
        () => expectError('1 < 2 < 3', 6, 'chained'));
    test('unknown function reports the name position',
        () => expectError('1 + nope(2)', 4, "Unknown function 'nope'"));
    test('wrong arity', () => expectError('abs(1, 2)', 0, 'expects 1'));
    test('missing ternary colon', () => expectError('a ? b', 5, "':'"));
    test(r'bare $', () => expectError(r'1 + $', 4, 'variable name'));
    test('unterminated braced variable',
        () => expectError(r'${abc', 0, 'Unterminated'));
    test('trailing dot in path', () => expectError('a.', 2, 'after'));
    test('missing list bracket', () => expectError('[1, 2', 5, "']'"));

    test('reports line and column', () {
      try {
        ast('1 +\n  2 +\n  )');
        fail('should throw');
      } on ParseError catch (e) {
        expect(e.line, 3);
        expect(e.column, 3);
        expect(e.toString(), contains('line 3, column 3'));
        expect(e.toString(), contains('^'));
      }
    });
  });
}
