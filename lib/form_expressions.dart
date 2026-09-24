/// A safe, sandboxed expression language for dynamic forms: calculated
/// fields, show/hide conditions, validation rules and text templates.
///
/// Start with [ExpressionEngine]: compile an [Expression] once and evaluate
/// it many times, or parse a [Template] for `{{field}}` piping.
library;

export 'src/dependencies.dart'
    show
        CalculationOrder,
        CalculationResult,
        evaluateCalculations,
        orderCalculations,
        orderDependencies;
export 'src/engine.dart'
    show Expression, ExpressionEngine, Template, mapResolver;
export 'src/errors.dart' show EvalError, ExpressionError, ParseError;
export 'src/evaluator.dart' show VariableResolver;
export 'src/functions.dart' show ExpressionFunction;
export 'src/limits.dart' show ExpressionLimits;
export 'src/values.dart' show formatValue;
