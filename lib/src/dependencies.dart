import 'dart:collection';

import 'engine.dart';
import 'errors.dart';
import 'evaluator.dart';

/// The evaluation order of a set of calculated fields.
class CalculationOrder {
  /// Creates an order result.
  const CalculationOrder({
    required this.order,
    required this.cycles,
    required this.blocked,
    required Map<String, Set<String>> dependencies,
  }) : _dependencies = dependencies;

  /// Fields that can be evaluated, each after everything it depends on.
  /// Independent fields keep their declaration order.
  final List<String> order;

  /// Groups of fields that depend on each other in a loop (strongly
  /// connected components), each listed in declaration order. A field that
  /// references itself forms a group of one.
  final List<List<String>> cycles;

  /// Fields outside any cycle that cannot be evaluated because they depend,
  /// directly or indirectly, on a cycle.
  final Set<String> blocked;

  final Map<String, Set<String>> _dependencies;

  /// Whether any circular dependency was found.
  bool get hasCycles => cycles.isNotEmpty;

  /// A concrete loop through the first field of each [cycles] entry, for
  /// error messages, such as `['a', 'b', 'a']`.
  List<List<String>> get cyclePaths => [
        for (final group in cycles) _loopThrough(group),
      ];

  List<String> _loopThrough(List<String> group) {
    final members = group.toSet();
    final start = group.first;
    // Breadth-first search inside the group for the shortest way back.
    final previous = <String, String>{};
    final queue = Queue<String>()..add(start);
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      for (final next in _dependencies[node] ?? const <String>{}) {
        if (!members.contains(next)) continue;
        if (next == start) {
          final path = [start];
          for (var n = node; n != start; n = previous[n]!) {
            path.insert(1, n);
          }
          return path..add(start);
        }
        if (previous.containsKey(next)) continue;
        previous[next] = node;
        queue.add(next);
      }
    }
    return [start, start];
  }

  @override
  String toString() {
    final loops = cyclePaths.map((p) => p.join(' -> ')).join('; ');
    return 'CalculationOrder(order: $order'
        '${hasCycles ? ', cycles: $loops' : ''}'
        '${blocked.isNotEmpty ? ', blocked: $blocked' : ''})';
  }
}

/// Orders a generic dependency graph: [dependencies] maps each name to the
/// names it needs first. Names that are not keys (such as plain input
/// fields) are treated as already available.
CalculationOrder orderDependencies(Map<String, Set<String>> dependencies) {
  final names = dependencies.keys.toList();
  final index = {for (var i = 0; i < names.length; i++) names[i]: i};
  // Edges restricted to known names.
  final deps = [
    for (final n in names)
      {
        for (final d in dependencies[n]!)
          if (index.containsKey(d)) index[d]!,
      },
  ];
  final dependents = List.generate(names.length, (_) => <int>[]);
  final waiting = List<int>.filled(names.length, 0);
  for (var i = 0; i < names.length; i++) {
    waiting[i] = deps[i].length;
    for (final d in deps[i]) {
      dependents[d].add(i);
    }
  }

  // Kahn's algorithm, always taking the earliest-declared ready field.
  final ready = SplayTreeSet<int>();
  for (var i = 0; i < names.length; i++) {
    if (waiting[i] == 0) ready.add(i);
  }
  final order = <String>[];
  final done = List<bool>.filled(names.length, false);
  while (ready.isNotEmpty) {
    final i = ready.first;
    ready.remove(i);
    done[i] = true;
    order.add(names[i]);
    for (final j in dependents[i]) {
      if (--waiting[j] == 0) ready.add(j);
    }
  }

  final components = _stronglyConnected(deps);
  final cycles = <List<String>>[];
  final inCycle = <int>{};
  for (final component in components) {
    final isLoop =
        component.length > 1 || deps[component.first].contains(component.first);
    if (!isLoop) continue;
    component.sort();
    inCycle.addAll(component);
    cycles.add([for (final i in component) names[i]]);
  }
  cycles.sort((a, b) => index[a.first]!.compareTo(index[b.first]!));

  final blocked = <String>{
    for (var i = 0; i < names.length; i++)
      if (!done[i] && !inCycle.contains(i)) names[i],
  };

  return CalculationOrder(
    order: List.unmodifiable(order),
    cycles: List.unmodifiable(cycles.map(List<String>.unmodifiable)),
    blocked: Set.unmodifiable(blocked),
    dependencies: {
      for (var i = 0; i < names.length; i++)
        names[i]: {for (final d in deps[i]) names[d]},
    },
  );
}

/// Kosaraju's algorithm with explicit stacks (no recursion), so very long
/// dependency chains cannot overflow the call stack.
List<List<int>> _stronglyConnected(List<Set<int>> edges) {
  final n = edges.length;
  final visited = List<bool>.filled(n, false);
  final finished = <int>[];
  for (var s = 0; s < n; s++) {
    if (visited[s]) continue;
    visited[s] = true;
    final stack = <(int, Iterator<int>)>[(s, edges[s].iterator)];
    while (stack.isNotEmpty) {
      final (node, it) = stack.last;
      if (it.moveNext()) {
        final next = it.current;
        if (!visited[next]) {
          visited[next] = true;
          stack.add((next, edges[next].iterator));
        }
      } else {
        stack.removeLast();
        finished.add(node);
      }
    }
  }

  final reverse = List.generate(n, (_) => <int>[]);
  for (var i = 0; i < n; i++) {
    for (final j in edges[i]) {
      reverse[j].add(i);
    }
  }
  final assigned = List<bool>.filled(n, false);
  final components = <List<int>>[];
  for (final s in finished.reversed) {
    if (assigned[s]) continue;
    final component = <int>[];
    final stack = [s];
    assigned[s] = true;
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      component.add(node);
      for (final next in reverse[node]) {
        if (!assigned[next]) {
          assigned[next] = true;
          stack.add(next);
        }
      }
    }
    components.add(component);
  }
  return components;
}

/// Whether [path] refers to the field [name] (`name` or `name.something`).
bool _refersTo(String path, String name) =>
    path == name || path.startsWith('$name.');

/// Orders calculated fields so that each one is evaluated after the fields
/// it references, and reports circular dependencies.
///
/// A field depends on another when one of its [Expression.variables] is the
/// other's name or starts with `name.`.
CalculationOrder orderCalculations(Map<String, Expression> calculations) {
  final names = calculations.keys.toList();
  return orderDependencies({
    for (final entry in calculations.entries)
      entry.key: {
        for (final path in entry.value.variables)
          for (final name in names)
            if (_refersTo(path, name)) name,
      },
  });
}

/// The outcome of [evaluateCalculations].
class CalculationResult {
  /// Creates a result.
  const CalculationResult({
    required this.values,
    required this.errors,
    required this.order,
  });

  /// Computed values by field name. Fields that failed map to `null`;
  /// fields in or blocked by cycles are absent.
  final Map<String, Object?> values;

  /// Evaluation errors by field name.
  final Map<String, EvalError> errors;

  /// The order used, including any cycles found.
  final CalculationOrder order;
}

/// Evaluates every calculated field in dependency order.
///
/// Each field sees the input [variables] (or [resolver]) plus the values of
/// the fields computed before it; a computed value shadows an input with the
/// same name. A failing field is recorded in [CalculationResult.errors] and
/// seen as `null` by its dependents. Fields in cycles are skipped.
CalculationResult evaluateCalculations(
  Map<String, Expression> calculations, {
  Map<String, Object?> variables = const {},
  VariableResolver? resolver,
}) {
  final order = orderCalculations(calculations);
  final base = resolver ?? mapResolver(variables);
  final values = <String, Object?>{};
  final computed = mapResolver(values);

  Object? layered(String path) {
    for (final name in values.keys) {
      if (_refersTo(path, name)) return computed(path);
    }
    return base(path);
  }

  final errors = <String, EvalError>{};
  for (final name in order.order) {
    try {
      values[name] = calculations[name]!.evaluate(resolver: layered);
    } on EvalError catch (e) {
      values[name] = null;
      errors[name] = e;
    }
  }
  return CalculationResult(values: values, errors: errors, order: order);
}
