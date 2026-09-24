import 'ast.dart';
import 'errors.dart';
import 'lexer.dart';
import 'limits.dart';
import 'token.dart';

/// Minimum and maximum argument counts of a function (`max == null` means
/// unbounded).
typedef Arity = ({int min, int? max});

/// Looks up the arity of a lower-cased function name; null when unknown.
typedef ArityLookup = Arity? Function(String name);

/// Recursive-descent parser producing a [Node] tree.
///
/// Grammar, loosest binding first:
///
/// ```text
/// expression  := ternary
/// ternary     := nullish ( '?' expression ':' expression )?
/// nullish     := or ( '??' or )*
/// or          := and ( ('or' | '||') and )*
/// and         := not ( ('and' | '&&') not )*
/// not         := ('not' | '!') not | equality
/// equality    := comparison ( ('==' | '!=') comparison )*
/// comparison  := additive ( ('<'|'<='|'>'|'>='|'in'|'not in') additive )?
/// additive    := multiplicative ( ('+' | '-') multiplicative )*
/// multiplicative := unary ( ('*' | '/' | '%') unary )*
/// unary       := ('-' | '+') unary | power
/// power       := postfix ( '^' unary )?
/// postfix     := primary ( '[' expression ']' )*
/// primary     := literal | list | variable | call | '(' expression ')'
/// ```
class Parser {
  /// Creates a parser over already-lexed [tokens].
  Parser(
    this._tokens, {
    required this.source,
    required this.limits,
    required this.functionArity,
  });

  /// Lexes and parses a stand-alone expression.
  static Node parseSource(
    String source, {
    required ExpressionLimits limits,
    required ArityLookup functionArity,
  }) {
    if (source.length > limits.maxLength) {
      throw ParseError(
        'Expression is too long (${source.length} characters, '
        'max ${limits.maxLength})',
        source: source,
        offset: limits.maxLength,
      );
    }
    final tokens = Lexer(source).tokenize();
    return Parser(
      tokens,
      source: source,
      limits: limits,
      functionArity: functionArity,
    ).parseAll();
  }

  final List<Token> _tokens;

  /// Full source text, used for error reports.
  final String source;

  /// Resource limits.
  final ExpressionLimits limits;

  /// Function arity lookup used to validate calls.
  final ArityLookup functionArity;

  int _index = 0;
  int _depth = 0;

  Token get _current => _tokens[_index];

  bool _check(TokenType type) => _current.type == type;

  Token _advance() {
    final t = _current;
    if (t.type != TokenType.eof) _index++;
    return t;
  }

  bool _match(TokenType type) {
    if (!_check(type)) return false;
    _advance();
    return true;
  }

  ParseError _error(String message, [int? offset]) =>
      ParseError(message, source: source, offset: offset ?? _current.offset);

  Token _expect(TokenType type, String what) {
    if (_check(type)) return _advance();
    throw _error("Expected '$what' but found ${_current.describe}");
  }

  void _enter() {
    if (++_depth > limits.maxDepth) {
      throw _error('Expression is nested too deeply (max ${limits.maxDepth})');
    }
  }

  void _exit() => _depth--;

  /// Parses the whole token stream as one expression. With [allowPipes],
  /// trailing `| filter` / `| filter(args)` segments are accepted and turned
  /// into calls whose first argument is the value so far.
  Node parseAll({bool allowPipes = false}) {
    if (_check(TokenType.eof)) throw _error('Empty expression');
    var node = _expression();
    if (allowPipes) {
      while (_match(TokenType.pipe)) {
        node = _filter(node);
      }
    }
    if (!_check(TokenType.eof)) {
      if (_check(TokenType.pipe)) {
        throw _error("Unexpected '|' (use '||' or 'or')");
      }
      throw _error('Unexpected ${_current.describe}');
    }
    return node;
  }

  Node _filter(Node value) {
    if (!_check(TokenType.identifier)) {
      throw _error("Expected a filter name after '|'");
    }
    final name = _advance();
    final args = <Node>[value];
    if (_match(TokenType.lparen)) args.addAll(_arguments());
    return _makeCall(name, args);
  }

  Node _expression() {
    _enter();
    final node = _ternary();
    _exit();
    return node;
  }

  Node _ternary() {
    final condition = _nullish();
    if (!_check(TokenType.question)) return condition;
    final at = _advance().offset;
    final then = _expression();
    _expect(TokenType.colon, ':');
    final otherwise = _expression();
    return ConditionalNode(condition, then, otherwise, at);
  }

  Node _nullish() {
    var left = _or();
    while (_check(TokenType.nullish)) {
      final at = _advance().offset;
      left = BinaryNode(BinaryOp.nullish, left, _or(), at);
    }
    return left;
  }

  Node _or() {
    var left = _and();
    while (_check(TokenType.or)) {
      final at = _advance().offset;
      left = BinaryNode(BinaryOp.or, left, _and(), at);
    }
    return left;
  }

  Node _and() {
    var left = _not();
    while (_check(TokenType.and)) {
      final at = _advance().offset;
      left = BinaryNode(BinaryOp.and, left, _not(), at);
    }
    return left;
  }

  Node _not() {
    if (!_check(TokenType.not)) return _equality();
    final at = _advance().offset;
    _enter();
    final operand = _not();
    _exit();
    return UnaryNode(UnaryOp.not, operand, at);
  }

  Node _equality() {
    var left = _comparison();
    while (_check(TokenType.eq) || _check(TokenType.neq)) {
      final token = _advance();
      final op = token.type == TokenType.eq ? BinaryOp.eq : BinaryOp.neq;
      left = BinaryNode(op, left, _comparison(), token.offset);
    }
    return left;
  }

  BinaryOp? _comparisonOp() => switch (_current.type) {
        TokenType.lt => BinaryOp.lt,
        TokenType.lte => BinaryOp.lte,
        TokenType.gt => BinaryOp.gt,
        TokenType.gte => BinaryOp.gte,
        TokenType.inKw => BinaryOp.inList,
        TokenType.not when _tokens[_index + 1].type == TokenType.inKw =>
          BinaryOp.notIn,
        _ => null,
      };

  Node _comparison() {
    final left = _additive();
    final op = _comparisonOp();
    if (op == null) return left;
    final at = _advance().offset;
    if (op == BinaryOp.notIn) _advance(); // the `in` of `not in`
    final node = BinaryNode(op, left, _additive(), at);
    if (_comparisonOp() != null) {
      throw _error(
        'Comparison operators cannot be chained; combine them with "and"',
      );
    }
    return node;
  }

  Node _additive() {
    var left = _multiplicative();
    while (_check(TokenType.plus) || _check(TokenType.minus)) {
      final token = _advance();
      final op = token.type == TokenType.plus ? BinaryOp.add : BinaryOp.sub;
      left = BinaryNode(op, left, _multiplicative(), token.offset);
    }
    return left;
  }

  Node _multiplicative() {
    var left = _unary();
    while (true) {
      final op = switch (_current.type) {
        TokenType.star => BinaryOp.mul,
        TokenType.slash => BinaryOp.div,
        TokenType.percent => BinaryOp.mod,
        _ => null,
      };
      if (op == null) return left;
      final at = _advance().offset;
      left = BinaryNode(op, left, _unary(), at);
    }
  }

  Node _unary() {
    if (!_check(TokenType.minus) && !_check(TokenType.plus)) return _power();
    final token = _advance();
    _enter();
    final operand = _unary();
    _exit();
    return UnaryNode(
      token.type == TokenType.minus ? UnaryOp.neg : UnaryOp.pos,
      operand,
      token.offset,
    );
  }

  Node _power() {
    final base = _postfix();
    if (!_check(TokenType.caret)) return base;
    final at = _advance().offset;
    _enter();
    final exponent = _unary();
    _exit();
    return BinaryNode(BinaryOp.pow, base, exponent, at);
  }

  Node _postfix() {
    var node = _primary();
    var entered = 0;
    while (_check(TokenType.lbracket)) {
      _advance();
      _enter();
      entered++;
      final index = _expression();
      _expect(TokenType.rbracket, ']');
      node = IndexNode(node, index, node.start);
    }
    _depth -= entered;
    return node;
  }

  Node _primary() {
    final token = _current;
    switch (token.type) {
      case TokenType.number:
      case TokenType.string:
        _advance();
        return LiteralNode(token.value, token.offset);
      case TokenType.trueKw:
        _advance();
        return LiteralNode(true, token.offset);
      case TokenType.falseKw:
        _advance();
        return LiteralNode(false, token.offset);
      case TokenType.nullKw:
        _advance();
        return LiteralNode(null, token.offset);
      case TokenType.lparen:
        _advance();
        final inner = _expression();
        _expect(TokenType.rparen, ')');
        return inner;
      case TokenType.lbracket:
        return _list();
      case TokenType.variable:
        _advance();
        return _path(token, [token.lexeme]);
      case TokenType.identifier:
        _advance();
        if (_match(TokenType.lparen)) {
          return _makeCall(token, _arguments());
        }
        return _path(token, [token.lexeme]);
      case TokenType.eof:
        throw _error('Unexpected end of expression');
      default:
        throw _error('Unexpected ${token.describe}');
    }
  }

  Node _list() {
    final open = _advance();
    final items = <Node>[];
    if (!_match(TokenType.rbracket)) {
      do {
        items.add(_expression());
      } while (_match(TokenType.comma));
      _expect(TokenType.rbracket, ']');
    }
    return ListNode(items, open.offset);
  }

  /// Parses a comma separated argument list; the `(` is already consumed.
  List<Node> _arguments() {
    final args = <Node>[];
    if (_match(TokenType.rparen)) return args;
    do {
      args.add(_expression());
    } while (_match(TokenType.comma));
    _expect(TokenType.rparen, ')');
    return args;
  }

  Node _path(Token first, List<String> segments) {
    while (_check(TokenType.dot)) {
      _advance();
      final t = _current;
      final isName = t.type == TokenType.identifier ||
          t.type == TokenType.trueKw ||
          t.type == TokenType.falseKw ||
          t.type == TokenType.nullKw ||
          t.type == TokenType.and ||
          t.type == TokenType.or ||
          t.type == TokenType.inKw ||
          (t.type == TokenType.not && t.lexeme != '!');
      if (isName) {
        segments.add(t.lexeme);
      } else if (t.type == TokenType.number &&
          RegExp(r'^\d+(\.\d+)*$').hasMatch(t.lexeme)) {
        // `items.1.2` lexes the tail as the number `1.2`.
        segments.addAll(t.lexeme.split('.'));
      } else {
        throw _error("Expected a name or index after '.'");
      }
      _advance();
    }
    return VariableNode(segments, first.offset);
  }

  Node _makeCall(Token name, List<Node> args) {
    final lower = name.lexeme.toLowerCase();
    final arity = lower == 'if' ? (min: 2, max: 3) : functionArity(lower);
    if (arity == null) {
      throw _error("Unknown function '${name.lexeme}'", name.offset);
    }
    final count = args.length;
    if (count < arity.min || (arity.max != null && count > arity.max!)) {
      throw _error(
        "Function '${name.lexeme}' expects ${_describeArity(arity)}, "
        'got $count',
        name.offset,
      );
    }
    return CallNode(lower, args, name.offset);
  }

  static String _describeArity(Arity a) {
    String plural(int n) => n == 1 ? '$n argument' : '$n arguments';
    if (a.max == null) return 'at least ${plural(a.min)}';
    if (a.max == a.min) return plural(a.min);
    return '${a.min} to ${a.max} arguments';
  }
}
