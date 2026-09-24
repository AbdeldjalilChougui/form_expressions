import 'errors.dart';
import 'token.dart';

const _keywords = <String, TokenType>{
  'true': TokenType.trueKw,
  'false': TokenType.falseKw,
  'null': TokenType.nullKw,
  'and': TokenType.and,
  'or': TokenType.or,
  'not': TokenType.not,
  'in': TokenType.inKw,
};

/// Largest integer that every Dart platform (including the web) represents
/// exactly.
const maxSafeInt = 9007199254740991;

/// Turns source text into [Token]s.
///
/// In template mode ([templateOpen] is set) lexing starts at [start] and
/// stops at the first `}}` that is not inside a string literal; [end] is then
/// the offset just after that `}}`.
class Lexer {
  /// Creates a lexer over [source] starting at [start].
  Lexer(this.source, {this.start = 0, this.templateOpen});

  /// The full text being lexed.
  final String source;

  /// Offset at which lexing begins.
  final int start;

  /// Offset of the `{{` that opened a template placeholder, or null when
  /// lexing a stand-alone expression.
  final int? templateOpen;

  int _pos = 0;

  /// Offset just after the last consumed character (after `}}` in template
  /// mode). Valid once [tokenize] has returned.
  int get end => _pos;

  bool get _template => templateOpen != null;

  ParseError _error(String message, int offset) =>
      ParseError(message, source: source, offset: offset);

  /// Returns all tokens, ending with a [TokenType.eof] token.
  List<Token> tokenize() {
    _pos = start;
    final tokens = <Token>[];
    while (true) {
      _skipWhitespace();
      if (_pos >= source.length) {
        if (_template) {
          throw _error(
              "Unterminated placeholder: expected '}}'", templateOpen!);
        }
        tokens.add(Token(TokenType.eof, '', _pos));
        return tokens;
      }
      final c = source[_pos];
      if (_template && c == '}' && _peek(1) == '}') {
        tokens.add(Token(TokenType.eof, '}}', _pos));
        _pos += 2;
        return tokens;
      }
      tokens.add(_next(tokens.isEmpty ? null : tokens.last));
    }
  }

  String? _peek(int ahead) {
    final i = _pos + ahead;
    return i < source.length ? source[i] : null;
  }

  void _skipWhitespace() {
    while (_pos < source.length && _isSpace(source.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  Token _next(Token? previous) {
    final c = source[_pos];
    final code = c.codeUnitAt(0);
    if (_isDigit(code)) return _number();
    if (c == '.' && _isDigitAt(_pos + 1) && !_endsValue(previous)) {
      return _number();
    }
    if (_isIdentStart(code)) return _identifier();
    if (c == r'$') return _variable();
    if (c == '"' || c == "'") return _string(c);
    return _operator(c);
  }

  static bool _endsValue(Token? t) =>
      t != null &&
      (t.type == TokenType.identifier ||
          t.type == TokenType.variable ||
          t.type == TokenType.number ||
          t.type == TokenType.rparen ||
          t.type == TokenType.rbracket);

  Token _number() {
    final begin = _pos;
    var isInt = true;
    while (_isDigitAt(_pos)) {
      _pos++;
    }
    if (_pos < source.length && source[_pos] == '.' && _isDigitAt(_pos + 1)) {
      isInt = false;
      _pos++;
      while (_isDigitAt(_pos)) {
        _pos++;
      }
    }
    if (_pos < source.length && (source[_pos] == 'e' || source[_pos] == 'E')) {
      var look = _pos + 1;
      if (look < source.length &&
          (source[look] == '+' || source[look] == '-')) {
        look++;
      }
      if (_isDigitAt(look)) {
        isInt = false;
        _pos = look;
        while (_isDigitAt(_pos)) {
          _pos++;
        }
      }
    }
    final text = source.substring(begin, _pos);
    num value;
    final asInt = isInt ? int.tryParse(text) : null;
    if (asInt != null && asInt <= maxSafeInt) {
      value = asInt;
    } else {
      value = double.parse(text.startsWith('.') ? '0$text' : text);
    }
    return Token(TokenType.number, text, begin, value);
  }

  Token _identifier() {
    final begin = _pos;
    while (_pos < source.length && _isIdentPart(source.codeUnitAt(_pos))) {
      _pos++;
    }
    final text = source.substring(begin, _pos);
    final keyword = _keywords[text.toLowerCase()];
    return Token(keyword ?? TokenType.identifier, text, begin);
  }

  Token _variable() {
    final begin = _pos;
    _pos++; // $
    if (_pos < source.length && source[_pos] == '{') {
      final close = source.indexOf('}', _pos + 1);
      if (close < 0) {
        throw _error("Unterminated '\${': expected '}'", begin);
      }
      final name = source.substring(_pos + 1, close).trim();
      if (name.isEmpty) throw _error('Empty variable name', begin);
      _pos = close + 1;
      return Token(TokenType.variable, name, begin);
    }
    if (_pos >= source.length || !_isIdentStart(source.codeUnitAt(_pos))) {
      throw _error(r"Expected a variable name after '$'", begin);
    }
    final nameStart = _pos;
    while (_pos < source.length && _isIdentPart(source.codeUnitAt(_pos))) {
      _pos++;
    }
    return Token(TokenType.variable, source.substring(nameStart, _pos), begin);
  }

  Token _string(String quote) {
    final begin = _pos;
    _pos++;
    final buffer = StringBuffer();
    while (true) {
      if (_pos >= source.length) {
        throw _error('Unterminated string', begin);
      }
      final c = source[_pos];
      if (c == quote) {
        _pos++;
        break;
      }
      if (c == r'\') {
        buffer.write(_escape());
        continue;
      }
      buffer.write(c);
      _pos++;
    }
    return Token(
      TokenType.string,
      source.substring(begin, _pos),
      begin,
      buffer.toString(),
    );
  }

  String _escape() {
    final at = _pos;
    final next = _peek(1);
    _pos += 2;
    switch (next) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case r'\':
      case '"':
      case "'":
      case '/':
        return next!;
      case 'u':
        return _unicodeEscape(at);
      default:
        throw _error(
          "Invalid escape sequence '\\${next ?? ''}'",
          at,
        );
    }
  }

  String _unicodeEscape(int at) {
    String hex;
    if (_peek(0) == '{') {
      final close = source.indexOf('}', _pos);
      if (close < 0 || close - _pos > 7) {
        throw _error('Invalid unicode escape', at);
      }
      hex = source.substring(_pos + 1, close);
      _pos = close + 1;
    } else {
      if (_pos + 4 > source.length) throw _error('Invalid unicode escape', at);
      hex = source.substring(_pos, _pos + 4);
      _pos += 4;
    }
    final code = int.tryParse(hex, radix: 16);
    if (code == null || hex.isEmpty || code > 0x10FFFF) {
      throw _error('Invalid unicode escape', at);
    }
    return String.fromCharCode(code);
  }

  Token _operator(String c) {
    final begin = _pos;
    final two = _pos + 1 < source.length ? source.substring(_pos, _pos + 2) : c;
    const doubles = <String, TokenType>{
      '&&': TokenType.and,
      '||': TokenType.or,
      '==': TokenType.eq,
      '!=': TokenType.neq,
      '<=': TokenType.lte,
      '>=': TokenType.gte,
      '??': TokenType.nullish,
    };
    final double = doubles[two];
    if (double != null) {
      _pos += 2;
      return Token(double, two, begin);
    }
    const singles = <String, TokenType>{
      '!': TokenType.not,
      '<': TokenType.lt,
      '>': TokenType.gt,
      '?': TokenType.question,
      ':': TokenType.colon,
      '+': TokenType.plus,
      '-': TokenType.minus,
      '*': TokenType.star,
      '/': TokenType.slash,
      '%': TokenType.percent,
      '^': TokenType.caret,
      '(': TokenType.lparen,
      ')': TokenType.rparen,
      '[': TokenType.lbracket,
      ']': TokenType.rbracket,
      ',': TokenType.comma,
      '.': TokenType.dot,
      '|': TokenType.pipe,
    };
    final single = singles[c];
    if (single != null) {
      _pos++;
      return Token(single, c, begin);
    }
    if (c == '=') {
      throw _error("Unexpected '=' (use '==' for equality comparison)", begin);
    }
    if (c == '&') throw _error("Unexpected '&' (use '&&' or 'and')", begin);
    throw _error("Unexpected character '$c'", begin);
  }

  bool _isDigitAt(int i) => i < source.length && _isDigit(source.codeUnitAt(i));

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0;

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      (c >= 0x80 && c != 0xA0 && !_isUnicodeSpace(c));

  static bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);

  static bool _isUnicodeSpace(int c) =>
      c == 0x2028 || c == 0x2029 || c == 0xFEFF || (c >= 0x2000 && c <= 0x200B);
}
