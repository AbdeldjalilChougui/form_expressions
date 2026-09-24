/// Kinds of lexical tokens.
enum TokenType {
  /// Numeric literal.
  number,

  /// String literal.
  string,

  /// Bare identifier (variable path segment or function name).
  identifier,

  /// `$name` or `${any name}` variable.
  variable,

  /// `true`.
  trueKw,

  /// `false`.
  falseKw,

  /// `null`.
  nullKw,

  /// `and` / `&&`.
  and,

  /// `or` / `||`.
  or,

  /// `not` / `!`.
  not,

  /// `in`.
  inKw,

  /// `+`.
  plus,

  /// `-`.
  minus,

  /// `*`.
  star,

  /// `/`.
  slash,

  /// `%`.
  percent,

  /// `^`.
  caret,

  /// `==`.
  eq,

  /// `!=`.
  neq,

  /// `<`.
  lt,

  /// `<=`.
  lte,

  /// `>`.
  gt,

  /// `>=`.
  gte,

  /// `??`.
  nullish,

  /// `?`.
  question,

  /// `:`.
  colon,

  /// `(`.
  lparen,

  /// `)`.
  rparen,

  /// `[`.
  lbracket,

  /// `]`.
  rbracket,

  /// `,`.
  comma,

  /// `.`.
  dot,

  /// `|` (template filter pipe).
  pipe,

  /// End of input (or `}}` when lexing a template placeholder).
  eof,
}

/// A lexical token with its position in the source.
class Token {
  /// Creates a token.
  const Token(this.type, this.lexeme, this.offset, [this.value]);

  /// The token kind.
  final TokenType type;

  /// The raw text (for variables, the name without `$`/braces).
  final String lexeme;

  /// Zero-based offset of the first character.
  final int offset;

  /// Decoded literal value for numbers and strings.
  final Object? value;

  /// A readable description for error messages.
  String get describe =>
      type == TokenType.eof ? 'end of expression' : "'$lexeme'";

  @override
  String toString() => '$type($lexeme)@$offset';
}
