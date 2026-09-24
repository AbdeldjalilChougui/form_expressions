import 'dart:convert' show jsonEncode;

/// Binary operators of the language.
enum BinaryOp {
  /// `+`
  add('+'),

  /// `-`
  sub('-'),

  /// `*`
  mul('*'),

  /// `/`
  div('/'),

  /// `%`
  mod('%'),

  /// `^`
  pow('^'),

  /// `==`
  eq('=='),

  /// `!=`
  neq('!='),

  /// `<`
  lt('<'),

  /// `<=`
  lte('<='),

  /// `>`
  gt('>'),

  /// `>=`
  gte('>='),

  /// `and` / `&&`
  and('and'),

  /// `or` / `||`
  or('or'),

  /// `??`
  nullish('??'),

  /// `in`
  inList('in'),

  /// `not in`
  notIn('not-in');

  const BinaryOp(this.symbol);

  /// Canonical symbol used in dumps and error messages.
  final String symbol;
}

/// Unary operators of the language.
enum UnaryOp {
  /// `-x`
  neg,

  /// `+x`
  pos,

  /// `not x` / `!x`
  not,
}

/// A node of the syntax tree. [start] is the offset used for error reports.
sealed class Node {
  const Node(this.start);

  /// Zero-based source offset associated with this node.
  final int start;

  /// Calls [visit] on every direct child.
  void forEachChild(void Function(Node child) visit);
}

/// A number, string, bool or null literal.
final class LiteralNode extends Node {
  /// Creates a literal.
  const LiteralNode(this.value, super.start);

  /// The literal value.
  final Object? value;

  @override
  void forEachChild(void Function(Node child) visit) {}

  @override
  String toString() => value is String ? jsonEncode(value) : '$value';
}

/// `[a, b, c]`.
final class ListNode extends Node {
  /// Creates a list literal.
  const ListNode(this.items, super.start);

  /// Element expressions.
  final List<Node> items;

  @override
  void forEachChild(void Function(Node child) visit) => items.forEach(visit);

  @override
  String toString() => '[${items.join(', ')}]';
}

/// A variable reference such as `$a.b` or `a.b`.
final class VariableNode extends Node {
  /// Creates a variable reference.
  VariableNode(this.segments, super.start) : path = segments.join('.');

  /// Path segments.
  final List<String> segments;

  /// Segments joined with dots.
  final String path;

  @override
  void forEachChild(void Function(Node child) visit) {}

  @override
  String toString() => '\$$path';
}

/// A prefix operator application.
final class UnaryNode extends Node {
  /// Creates a unary node; [start] is the operator offset.
  const UnaryNode(this.op, this.operand, super.start);

  /// The operator.
  final UnaryOp op;

  /// The operand.
  final Node operand;

  @override
  void forEachChild(void Function(Node child) visit) => visit(operand);

  @override
  String toString() => '(${op.name} $operand)';
}

/// An infix operator application.
final class BinaryNode extends Node {
  /// Creates a binary node; [start] is the operator offset.
  const BinaryNode(this.op, this.left, this.right, super.start);

  /// The operator.
  final BinaryOp op;

  /// Left operand.
  final Node left;

  /// Right operand.
  final Node right;

  @override
  void forEachChild(void Function(Node child) visit) {
    visit(left);
    visit(right);
  }

  @override
  String toString() => '(${op.symbol} $left $right)';
}

/// `cond ? then : otherwise`.
final class ConditionalNode extends Node {
  /// Creates a conditional; [start] is the `?` offset.
  const ConditionalNode(this.condition, this.then, this.otherwise, super.start);

  /// The condition.
  final Node condition;

  /// Value when the condition holds.
  final Node then;

  /// Value otherwise.
  final Node otherwise;

  @override
  void forEachChild(void Function(Node child) visit) {
    visit(condition);
    visit(then);
    visit(otherwise);
  }

  @override
  String toString() => '(? $condition $then $otherwise)';
}

/// A function call; [name] is lower-cased.
final class CallNode extends Node {
  /// Creates a call; [start] is the function name offset.
  const CallNode(this.name, this.args, super.start);

  /// Lower-cased function name.
  final String name;

  /// Argument expressions.
  final List<Node> args;

  @override
  void forEachChild(void Function(Node child) visit) => args.forEach(visit);

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// `target[index]`.
final class IndexNode extends Node {
  /// Creates an index node; [start] is the target offset.
  const IndexNode(this.target, this.index, super.start);

  /// The indexed value.
  final Node target;

  /// The index expression.
  final Node index;

  @override
  void forEachChild(void Function(Node child) visit) {
    visit(target);
    visit(index);
  }

  @override
  String toString() => '(index $target $index)';
}

/// Collects variable paths and function names referenced anywhere in [root].
void collectReferences(
  Node root, {
  required Set<String> variables,
  required Set<String> functions,
}) {
  // Iterative walk: trees are depth-limited, but this keeps analysis cheap.
  final stack = <Node>[root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is VariableNode) variables.add(node.path);
    if (node is CallNode) functions.add(node.name);
    node.forEachChild(stack.add);
  }
}
