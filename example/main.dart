import 'package:form_expressions/form_expressions.dart';

void main() {
  final engine = ExpressionEngine()
    // Custom functions are plain Dart closures over evaluated arguments.
    ..register('vat', (args) => (args[0]! as num) * 0.19,
        minArgs: 1, maxArgs: 1);

  // Answers as a form might store them.
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
  final order = orderCalculations(calculations);
  print('Evaluation order: ${order.order}'); // [subtotal, total, is_adult]

  final result = evaluateCalculations(calculations, variables: answers);
  print('Calculated: ${result.values}');

  // Show/hide condition.
  final showTaxId = engine.compile(r'$country in ["DZ", "TN"] and is_adult');
  print('Show tax id: ${showTaxId.evaluateBool(variables: {
        ...answers,
        ...result.values,
      })}');

  // Dependency analysis for a single expression.
  print('Depends on: ${showTaxId.variables}'); // {country, is_adult}

  // Text piping with filters and fallbacks.
  final greeting = engine.template(
      'Hello {{ name | upper }}, your total is {{ total | round(2) }} DZD. '
      'Coupon: {{ coupon ?? "none" }}.');
  print(greeting.render(variables: {...answers, ...result.values}));

  // Errors are typed and carry positions.
  try {
    engine.compile('1 + * 2');
  } on ParseError catch (e) {
    print(e);
  }
  try {
    engine.compile('total / count').evaluate(variables: {'total': 5});
  } on EvalError catch (e) {
    print(e.message);
  }
}
