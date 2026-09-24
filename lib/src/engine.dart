import 'ast.dart';
import 'errors.dart';
import 'evaluator.dart';
import 'functions.dart';
import 'lexer.dart';
import 'limits.dart';
import 'parser.dart';
import 'values.dart';

part 'template.dart';

final _namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
const _reservedNames = {
  'if',
  'true',
  'false',
  'null',
  'and',
  'or',
  'not',
  'in'
};

/// Compiles expressions and templates and holds the function table they may
/// call.
///
/// An engine is cheap to create. Keep one per set of custom functions and
/// reuse compiled [Expression]s: parse once, evaluate many times.
///
/// ```dart
/// final engine = ExpressionEngine();
/// final total = engine.compile('price * qty');
/// total.evaluate(variables: {'price': 2.5, 'qty': 4}); // 10.0
/// ```
class ExpressionEngine {
  /// Creates an engine with the built-in functions.
  ///
  /// [clock] supplies the current time for `today()` and `age()`; it
  /// defaults to [DateTime.now].
  ExpressionEngine({
    this.limits = const ExpressionLimits(),
    DateTime Function()? clock,
  }) {
    limits.validate();
    _functions.addAll(builtinFunctions(clock ?? DateTime.now));
    _builtinNames.addAll(_functions.keys);
  }

  /// Resource limits applied to everything this engine compiles.
  final ExpressionLimits limits;

  final Map<String, FunctionDefinition> _functions = {};
  final Set<String> _builtinNames = {};

  /// Registers a custom function callable as `name(...)`.
  ///
  /// Names are case-insensitive. [minArgs]/[maxArgs] are checked when an
  /// expression is compiled ([maxArgs] null means unbounded). Replacing an
  /// existing function, built-in or custom, requires [replace]. Expressions
  /// compiled earlier see the new implementation.
  void register(
    String name,
    ExpressionFunction function, {
    int minArgs = 0,
    int? maxArgs,
    bool replace = false,
  }) {
    if (!_namePattern.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Not a valid function name');
    }
    final lower = name.toLowerCase();
    if (_reservedNames.contains(lower)) {
      throw ArgumentError.value(name, 'name', 'Reserved word');
    }
    if (minArgs < 0 || (maxArgs != null && maxArgs < minArgs)) {
      throw ArgumentError('Invalid argument range $minArgs..$maxArgs');
    }
    if (_functions.containsKey(lower) && !replace) {
      final what = _builtinNames.contains(lower) ? 'built-in' : 'registered';
      throw ArgumentError.value(
        name,
        'name',
        'A $what function with this name exists; pass replace: true',
      );
    }
    _functions[lower] =
        FunctionDefinition(function, minArgs: minArgs, maxArgs: maxArgs);
  }

  /// Whether a function called [name] (case-insensitive) is available.
  bool hasFunction(String name) {
    final lower = name.toLowerCase();
    return lower == 'if' || _functions.containsKey(lower);
  }

  /// Lower-cased names of all callable functions, including `if`.
  Iterable<String> get functionNames => ['if', ..._functions.keys];

  /// The accepted argument counts of [name], or null if it is unknown.
  ({int min, int? max})? arityOf(String name) {
    final lower = name.toLowerCase();
    if (lower == 'if') return (min: 2, max: 3);
    final def = _functions[lower];
    return def == null ? null : (min: def.minArgs, max: def.maxArgs);
  }

  /// Parses [source] into a reusable [Expression].
  ///
  /// Throws a [ParseError] for syntax errors, unknown functions, wrong
  /// argument counts, or input exceeding [limits].
  Expression compile(String source) {
    final root = Parser.parseSource(
      source,
      limits: limits,
      functionArity: arityOf,
    );
    return Expression._(this, source, root);
  }

  /// Parses [source] as a text template with `{{ ... }}` placeholders.
  ///
  /// See [Template] for the syntax. Throws a [ParseError] on invalid input.
  Template template(String source) => Template.parse(this, source);

  /// Compiles and evaluates [source] in one step.
  ///
  /// Prefer [compile] when the same expression is evaluated repeatedly.
  Object? evaluate(
    String source, {
    Map<String, Object?> variables = const {},
    VariableResolver? resolver,
  }) =>
      compile(source).evaluate(variables: variables, resolver: resolver);

  Object? _evaluateNode(
    Node root,
    String source, {
    required Map<String, Object?> variables,
    required VariableResolver? resolver,
  }) =>
      Evaluator(
        source: source,
        resolver: resolver ?? mapResolver(variables),
        functions: _functions,
        maxDepth: limits.maxDepth,
      ).evaluate(root);
}

/// A compiled expression. Immutable and safe to evaluate many times,
/// including concurrently with different variables.
class Expression {
  Expression._(this._engine, this.source, this._root) {
    collectReferences(_root, variables: _variables, functions: _functions);
  }

  final ExpressionEngine _engine;
  final Node _root;
  final Set<String> _variables = {};
  final Set<String> _functions = {};

  /// The original source text.
  final String source;

  /// Every variable path the expression references (for example
  /// `{'price', 'address.city'}`), including ones in branches that a given
  /// evaluation may skip. Use it to build a dependency graph.
  Set<String> get variables => Set.unmodifiable(_variables);

  /// Lower-cased names of the functions the expression calls.
  Set<String> get functions => Set.unmodifiable(_functions);

  /// Evaluates the expression.
  ///
  /// Variables are looked up with [resolver] when given, otherwise in
  /// [variables] (see [mapResolver] for how dotted paths are resolved).
  /// Returns `null`, a [num], [String], [bool], [DateTime], or a [List].
  /// Throws an [EvalError] on type mismatches, division by zero and similar.
  Object? evaluate({
    Map<String, Object?> variables = const {},
    VariableResolver? resolver,
  }) =>
      _engine._evaluateNode(
        _root,
        source,
        variables: variables,
        resolver: resolver,
      );

  /// Evaluates the expression as a condition, for show/hide and validation
  /// rules. `null` counts as `false`; any other non-bool is an [EvalError].
  bool evaluateBool({
    Map<String, Object?> variables = const {},
    VariableResolver? resolver,
  }) {
    final value = evaluate(variables: variables, resolver: resolver);
    if (value is bool) return value;
    if (value == null) return false;
    throw EvalError(
      'Expected the expression to produce a bool, got ${typeName(value)}',
      source: source,
      offset: _root.start,
    );
  }

  /// Evaluates the expression and requires a number, for calculated fields.
  /// A non-number, including `null`, is an [EvalError].
  num evaluateNum({
    Map<String, Object?> variables = const {},
    VariableResolver? resolver,
  }) {
    final value = evaluate(variables: variables, resolver: resolver);
    if (value is num) return value;
    throw EvalError(
      'Expected the expression to produce a number, got ${typeName(value)}',
      source: source,
      offset: _root.start,
    );
  }

  @override
  String toString() => 'Expression($source)';
}

/// Creates a [VariableResolver] backed by [variables].
///
/// A path such as `address.city` is first looked up as a flat key; if absent
/// it walks nested maps by key and lists by integer index. Missing entries
/// resolve to `null`.
VariableResolver mapResolver(Map<String, Object?> variables) => (path) {
      if (variables.containsKey(path)) return variables[path];
      Object? current = variables;
      for (final segment in path.split('.')) {
        if (current is Map) {
          current = current[segment];
        } else if (current is List) {
          final i = int.tryParse(segment);
          if (i == null || i < 0 || i >= current.length) return null;
          current = current[i];
        } else {
          return null;
        }
      }
      return current;
    };
