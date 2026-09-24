# form_expressions

A safe, sandboxed expression language for dynamic forms. Use it for calculated fields, show/hide
conditions, validation rules and `{{field}}` text piping. It is pure Dart and never evaluates Dart
code.

[![pub package](https://img.shields.io/pub/v/form_expressions.svg)](https://pub.dev/packages/form_expressions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- **A proper pipeline.** A lexer feeds a recursive-descent parser, which builds an AST for the
  evaluator. Compile an expression once and evaluate it many times.
- **Types:** number, string, bool, null, list and date. Maps from your data are reachable
  through paths.
- **Operators:**
  - `+ - * / % ^`, with standard precedence and `^` right-associative;
  - unary `-` and `+`;
  - `== != < <= > >=`;
  - `and`/`or`/`not`, also written `&&`/`||`/`!`;
  - `in` and `not in`;
  - the ternary `a ? b : c` and the null fallback `a ?? b`;
  - list literals `[1, 2]`, indexing `xs[0]`, and string concatenation with `+`.
- **Variables:** write `$field`, a bare `field`, or `${any-name}`. Dotted paths such as
  `address.city` and `items.0.price` also work. They are resolved from a `Map` or from your own
  resolver callback.
- **Built-in functions:**
  - maths: `sum min max avg abs round(x, n) floor ceil`;
  - general: `if len count contains isEmpty number string`;
  - dates: `today date age dateDiff addDays`;
  - strings: `upper lower trim concat`.
- **Custom functions:** register them with argument-count checks. The checks run at compile time.
- **Static analysis:** `expression.variables` lists every referenced path.
  `orderCalculations` sorts calculated fields topologically and reports circular dependencies.
  `evaluateCalculations` evaluates the whole set in that order.
- **Typed errors:** `ParseError` and `EvalError` carry the offset, line and column, and a caret
  snippet. Division by zero, type mismatches and failing custom functions give clear errors,
  never crashes.
- **Templates:** `{{name}}`, `{{price * qty}}`, `{{name | trim | upper}}`, `{{ratio | round(2)}}`,
  `{{name ?? "friend"}}`, and `\{{` for a literal `{{`.
- **Limits:** caps on expression length, template length and nesting depth, so hostile input
  cannot exhaust the stack or CPU.

## Install

```sh
dart pub add form_expressions
```

## Usage

```dart
import 'package:form_expressions/form_expressions.dart';

void main() {
  final engine = ExpressionEngine()
    ..register('vat', (args) => (args[0]! as num) * 0.19,
        minArgs: 1, maxArgs: 1);

  final answers = <String, Object?>{
    'name': 'amina',
    'birth_date': '1994-05-17',
    'country': 'DZ',
    'items': [
      {'price': 1200, 'qty': 2},
      {'price': 450, 'qty': 1},
    ],
    'discount': null,
  };

  // Calculated fields: parse once, evaluate whenever an answer changes.
  final calculations = {
    'total': engine.compile('subtotal + vat(subtotal) - (discount ?? 0)'),
    'subtotal': engine
        .compile('items.0.price * items.0.qty + items.1.price * items.1.qty'),
    'is_adult': engine.compile('age(birth_date) >= 18'),
  };
  final result = evaluateCalculations(calculations, variables: answers);
  print(result.values); // {subtotal: 2850, total: 3391.5, is_adult: true}

  // Show/hide condition.
  final showTaxId = engine.compile(r'$country in ["DZ", "TN"] and is_adult');
  print(showTaxId.evaluateBool(variables: {...answers, ...result.values}));
  print(showTaxId.variables); // {country, is_adult}

  // Text piping.
  final greeting = engine.template(
      'Hello {{ name | upper }}, total {{ total | round(2) }} DZD. '
      'Coupon: {{ coupon ?? "none" }}.');
  print(greeting.render(variables: {...answers, ...result.values}));

  // Typed errors with positions.
  try {
    engine.compile('1 + * 2');
  } on ParseError catch (e) {
    print(e); // ParseError: Unexpected '*' at line 1, column 5 ...
  }
}
```

### Evaluating against your own data

```dart
final expr = engine.compile('customer.age >= 18');
expr.evaluate(resolver: (path) => myStore.lookup(path)); // path == 'customer.age'
```

### Circular dependencies

```dart
final order = orderCalculations({
  'a': engine.compile('b + 1'),
  'b': engine.compile('a + 1'),
  'c': engine.compile('a * 2'),
});
order.cycles;  // [[a, b]]
order.blocked; // {c}
print(order);  // CalculationOrder(order: [], cycles: a -> b -> a, blocked: {c})
```

## Language reference

Precedence runs from loosest to tightest. Operators on the same line share a level.

| Level | Operators | Associativity |
|---|---|---|
| 1 | `a ? b : c` | right |
| 2 | `??` | left |
| 3 | `or` `\|\|` | left |
| 4 | `and` `&&` | left |
| 5 | `not` `!` (prefix) | – |
| 6 | `==` `!=` | left |
| 7 | `<` `<=` `>` `>=` `in` `not in` | cannot chain |
| 8 | `+` `-` | left |
| 9 | `*` `/` `%` | left |
| 10 | unary `-` `+` | – |
| 11 | `^` | right (`-2 ^ 2` is `-4`) |
| 12 | `x[i]`, calls, literals, `( )` | – |

`not` binds looser than comparisons, so `not a == b` means `not (a == b)`.

Semantics worth knowing:

- **Numbers.** Integer arithmetic stays integral. If a result would leave the exactly
  representable range (±2^53), it switches to a double instead of wrapping. `/` always returns
  a double. `%` is Euclidean, so `-7 % 3` is `2`. A result that is infinite or NaN is an
  `EvalError`.
- **Conditions.** `and`, `or`, `not`, `?:` and `if()` accept bools. `null` counts as `false`;
  any other type is an `EvalError`. `and`, `or`, `??`, `?:` and `if()` all short-circuit.
- **Null.** Ordering comparisons with `null` (`$age > 18` when the age is empty) are `false`.
  Arithmetic with `null` is an error whose message suggests `??`. `x in null` is `false`.
  `sum`, `min`, `max`, `avg` and `count` skip empty values.
- **Equality** is structural. Numbers compare by value (`1 == 1.0`), dates by instant, and lists
  element by element. Values of different types are unequal; that is not an error.
- **`+` with a string** concatenates. The other side is formatted as templates format it, with
  `null` as the empty string.
- **Dates** come from your data as `DateTime` values. `date()`, `age()`, `dateDiff()` and
  `addDays()` also accept ISO-8601 strings. `dateDiff(from, to, unit)` returns whole `days`
  (the default), `weeks`, `months` or `years`. It counts calendar days, so daylight-saving
  shifts do not matter. `age()` counts completed years; someone born on 29 February has their
  birthday on 1 March in non-leap years.
- **`round(x, n)`** rounds half away from zero at `n` decimals, and `n` may be negative. It
  corrects binary noise, so `round(1.005, 2)` is `1.01`.
- **`isEmpty`** is true for `null`, blank strings, and empty lists and maps. `count` counts values
  that are not empty.
- **Function names and keywords** are case-insensitive.

## Security model

- The grammar has no member access, no method calls on values, no assignment and no loops. A
  path such as `a.b` is only a key handed to your resolver.
- Only built-in functions and functions you register can run. An unknown name is a
  `ParseError` at compile time.
- Host values must be `null`, `num`, `String`, `bool`, `DateTime`, an `Iterable` or a `Map`.
  Anything else is an `EvalError`, as is data nested deeper than `maxDepth`; that includes
  self-referencing lists.
- `ExpressionLimits` sets `maxLength` (4096 by default), `maxDepth` (64) and
  `maxTemplateLength` (65536). Deep nesting becomes a `ParseError`, never a stack overflow. Long
  flat chains such as `1 + 1 + … + 1` are evaluated iteratively.

## Migrating from a simple `{{field}}` replacer

- Any `{{field}}` placeholder is now an expression. An unknown field renders as an empty string
  instead of being left intact; write `{{field ?? "..."}}` to choose the text.
- The single-brace `{field}` form is not supported. Use `{{field}}`.
- Division by zero is now an `EvalError`; it no longer returns `0`. Comparisons return real
  bools instead of `1.0`/`0.0`.

## Limitations

- There are no user-defined variables, lambdas or loops. That is by design.
- Numbers are Dart `num`. There is no decimal type, so `0.1 + 0.2` is `0.30000000000000004`.
  Use `round(x, n)` for display.
- Dates carry no time-zone database. They are compared as the `DateTime` instants you supply,
  and `today()` uses the engine's clock (local time unless the clock returns UTC).
- String ordering compares UTF-16 code units. It is not locale-aware collation.
- Number formatting in templates is not localised: there are no thousands separators or locale
  decimal marks. Register a custom filter for that.

## License

MIT. See [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
