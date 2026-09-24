import 'errors.dart';
import 'lexer.dart' show maxSafeInt;

/// Name of a runtime value's type as shown in error messages:
/// `number`, `string`, `bool`, `null`, `list`, `date` or `map`.
String typeName(Object? value) => switch (value) {
      null => 'null',
      num() => 'number',
      String() => 'string',
      bool() => 'bool',
      DateTime() => 'date',
      List<Object?>() => 'list',
      Map<Object?, Object?>() => 'map',
      _ => value.runtimeType.toString(),
    };

/// Converts host data into the value space of the language.
///
/// Accepted: `null`, [num], [String], [bool], [DateTime], [Iterable]
/// (converted to a list) and [Map] (usable for equality and paths).
/// Anything else, or nesting deeper than [maxDepth], throws [EvalFailure].
Object? normalizeValue(Object? value, int maxDepth) {
  if (maxDepth < 0) {
    throw EvalFailure('Value is nested too deeply');
  }
  switch (value) {
    case null || num() || String() || bool() || DateTime():
      return value;
    case Iterable<Object?>():
      return List<Object?>.unmodifiable(
          value.map((e) => normalizeValue(e, maxDepth - 1)));
    case Map<Object?, Object?>():
      return Map<Object?, Object?>.unmodifiable(
          value.map((k, v) => MapEntry(k, normalizeValue(v, maxDepth - 1))));
    default:
      throw EvalFailure('Value has unsupported type ${value.runtimeType}');
  }
}

/// Structural equality used by `==`, `!=`, `in` and `contains`.
///
/// Numbers compare by value (`1 == 1.0`), dates by instant, lists and maps
/// element-wise. Values of different types are never equal.
bool valuesEqual(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is DateTime && b is DateTime) return a.isAtSameMomentAs(b);
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!valuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !valuesEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Formats a value for display, as templates and string concatenation do.
///
/// `null` becomes the empty string, integral doubles lose their `.0`, lists
/// are joined with `", "`, and dates at midnight print as `yyyy-MM-dd`
/// (other dates use ISO 8601).
String formatValue(Object? value) => switch (value) {
      null => '',
      String() => value,
      double()
          when value.isFinite &&
              value == value.truncateToDouble() &&
              value.abs() <= maxSafeInt =>
        value.toInt().toString(),
      num() || bool() => value.toString(),
      DateTime() => _formatDate(value),
      List<Object?>() => value.map(formatValue).join(', '),
      Map<Object?, Object?>() => '{${value.entries.map(
            (e) => '${formatValue(e.key)}: ${formatValue(e.value)}',
          ).join(', ')}}',
      _ => value.toString(),
    };

String _formatDate(DateTime d) {
  final isMidnight = d.hour == 0 &&
      d.minute == 0 &&
      d.second == 0 &&
      d.millisecond == 0 &&
      d.microsecond == 0;
  if (!isMidnight) return d.toIso8601String();
  String two(int n) => n.toString().padLeft(2, '0');
  final y = d.year.toString().padLeft(4, '0');
  return '$y-${two(d.month)}-${two(d.day)}';
}

/// Returns a number as an [int] when it is integral and exactly
/// representable, otherwise as a [double].
num tidyNumber(num value) {
  if (value is int) return value;
  if (value.isFinite &&
      value == value.truncateToDouble() &&
      value.abs() <= maxSafeInt) {
    return value.toInt();
  }
  return value;
}
