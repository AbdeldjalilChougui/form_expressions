import 'dart:math' as math;

import 'errors.dart';
import 'lexer.dart' show maxSafeInt;
import 'values.dart';

/// Signature of a function callable from expressions.
///
/// Arguments are already evaluated and normalised (numbers, strings, bools,
/// `null`, lists, dates, maps). The return value must be one of those types.
/// Throwing any exception makes the evaluation fail with an `EvalError`
/// that names the function.
typedef ExpressionFunction = Object? Function(List<Object?> args);

/// A registered function and its accepted argument counts.
class FunctionDefinition {
  /// Creates a definition.
  const FunctionDefinition(this.body, {this.minArgs = 0, this.maxArgs});

  /// The implementation.
  final ExpressionFunction body;

  /// Minimum number of arguments.
  final int minArgs;

  /// Maximum number of arguments, or null for unbounded.
  final int? maxArgs;
}

Never _fail(String message) => throw EvalFailure(message);

Iterable<num> _numbers(String fn, List<Object?> args) sync* {
  for (final a in args) {
    if (a == null) continue;
    if (a is num) {
      yield a;
    } else if (a is List<Object?>) {
      yield* _numbers(fn, a);
    } else {
      _fail('$fn() expects numbers, got ${typeName(a)}');
    }
  }
}

num _num(String fn, Object? value) => value is num
    ? value
    : _fail('$fn() expects a number, got ${typeName(value)}');

int _int(String fn, Object? value) {
  final n = _num(fn, value);
  if (n != n.truncateToDouble() || !n.isFinite) {
    _fail('$fn() expects an integer, got $n');
  }
  return n.toInt();
}

String? _str(String fn, Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  _fail('$fn() expects a string, got ${typeName(value)}');
}

/// Converts a date or ISO-8601 string to a [DateTime]; null stays null.
DateTime? toDate(String fn, Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) _fail('$fn() could not parse "$value" as a date');
    return parsed;
  }
  _fail('$fn() expects a date, got ${typeName(value)}');
}

num _roundTo(num x, int digits) {
  if (digits < -15 || digits > 15) _fail('round() digits must be in -15..15');
  if (x is int && digits >= 0) return x;
  if (!x.isFinite) _fail('round() expects a finite number');
  if (digits == 0) return _roundInt(x);
  if (digits < 0) {
    final f = math.pow(10, -digits);
    return tidyNumber(_roundInt(x / f) * f);
  }
  final f = math.pow(10, digits);
  // Re-reading the scaled value at 15 significant digits removes binary
  // representation noise, so round(1.005, 2) is 1.01 as a person expects.
  final scaled = double.parse((x * f).toStringAsPrecision(15));
  return scaled.round() / f;
}

num _roundInt(num x) {
  if (x is int) return x;
  return x.abs() > maxSafeInt ? x.roundToDouble() : x.round();
}

num _floorCeil(String fn, Object? value, bool floor) {
  final x = _num(fn, value);
  if (x is int) return x;
  final r = floor ? x.floorToDouble() : x.ceilToDouble();
  return tidyNumber(r);
}

bool _isEmptyValue(Object? v) =>
    v == null ||
    (v is String && v.trim().isEmpty) ||
    (v is List<Object?> && v.isEmpty) ||
    (v is Map<Object?, Object?> && v.isEmpty);

DateTime _dateOnlyUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _wholeMonths(DateTime from, DateTime to) {
  var months = (to.year - from.year) * 12 + (to.month - from.month);
  if (to.day < from.day) months--;
  return months;
}

int _dateDiff(DateTime from, DateTime to, String unit) {
  switch (unit) {
    case 'days':
    case 'weeks':
      final days =
          _dateOnlyUtc(to).difference(_dateOnlyUtc(from)).inHours ~/ 24;
      return unit == 'days' ? days : days ~/ 7;
    case 'months':
    case 'years':
      final forward = !_dateOnlyUtc(to).isBefore(_dateOnlyUtc(from));
      final months = forward ? _wholeMonths(from, to) : -_wholeMonths(to, from);
      return unit == 'months' ? months : months ~/ 12;
    default:
      _fail('dateDiff() unit must be "days", "weeks", "months" or "years", '
          'got "$unit"');
  }
}

bool _contains(String fn, Object? haystack, Object? needle) {
  if (haystack == null) return false;
  if (haystack is List<Object?>) {
    return haystack.any((e) => valuesEqual(e, needle));
  }
  if (haystack is String) {
    if (needle is! String) {
      _fail('$fn() needs a string to search a string, got ${typeName(needle)}');
    }
    return haystack.contains(needle);
  }
  _fail('$fn() expects a list or string, got ${typeName(haystack)}');
}

/// Membership test shared by the `in` operator and `contains()`.
bool containsValue(Object? haystack, Object? needle) =>
    _contains('in', haystack, needle);

/// Builds the built-in function table. [clock] supplies "now" for date
/// functions.
Map<String, FunctionDefinition> builtinFunctions(DateTime Function() clock) {
  DateTime today() {
    final now = clock();
    return now.isUtc
        ? DateTime.utc(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day);
  }

  return {
    // --- maths ---
    'sum': FunctionDefinition(
      (a) => _numbers('sum', a).fold<num>(0, (x, y) => x + y),
    ),
    'min': FunctionDefinition((a) {
      final nums = _numbers('min', a).toList();
      return nums.isEmpty ? null : nums.reduce(math.min);
    }),
    'max': FunctionDefinition((a) {
      final nums = _numbers('max', a).toList();
      return nums.isEmpty ? null : nums.reduce(math.max);
    }),
    'avg': FunctionDefinition((a) {
      final nums = _numbers('avg', a).toList();
      if (nums.isEmpty) return null;
      return nums.fold<num>(0, (x, y) => x + y) / nums.length;
    }),
    'abs': FunctionDefinition((a) => _num('abs', a[0]).abs(),
        minArgs: 1, maxArgs: 1),
    'round': FunctionDefinition(
      (a) =>
          _roundTo(_num('round', a[0]), a.length > 1 ? _int('round', a[1]) : 0),
      minArgs: 1,
      maxArgs: 2,
    ),
    'floor': FunctionDefinition((a) => _floorCeil('floor', a[0], true),
        minArgs: 1, maxArgs: 1),
    'ceil': FunctionDefinition((a) => _floorCeil('ceil', a[0], false),
        minArgs: 1, maxArgs: 1),

    // --- general ---
    'len': FunctionDefinition(
      (a) => switch (a[0]) {
        null => 0,
        final String s => s.length,
        final List<Object?> l => l.length,
        final Map<Object?, Object?> m => m.length,
        final other => _fail('len() expects a string or list, got '
            '${typeName(other)}'),
      },
      minArgs: 1,
      maxArgs: 1,
    ),
    'count': FunctionDefinition((a) {
      var n = 0;
      void visit(Object? v) {
        if (v is List<Object?>) {
          v.forEach(visit);
        } else if (!_isEmptyValue(v)) {
          n++;
        }
      }

      a.forEach(visit);
      return n;
    }),
    'contains': FunctionDefinition((a) => _contains('contains', a[0], a[1]),
        minArgs: 2, maxArgs: 2),
    'isempty':
        FunctionDefinition((a) => _isEmptyValue(a[0]), minArgs: 1, maxArgs: 1),
    'number': FunctionDefinition(
      (a) {
        final v = a[0];
        if (v == null || v is num) return v;
        if (v is String) {
          final t = v.trim();
          if (t.isEmpty) return null;
          final parsed = int.tryParse(t) ?? double.tryParse(t);
          if (parsed == null || !parsed.isFinite) {
            _fail('number() could not parse "$v"');
          }
          return parsed;
        }
        if (v is bool) return v ? 1 : 0;
        _fail('number() cannot convert ${typeName(v)}');
      },
      minArgs: 1,
      maxArgs: 1,
    ),
    'string':
        FunctionDefinition((a) => formatValue(a[0]), minArgs: 1, maxArgs: 1),

    // --- strings ---
    'upper': FunctionDefinition((a) => _str('upper', a[0])?.toUpperCase(),
        minArgs: 1, maxArgs: 1),
    'lower': FunctionDefinition((a) => _str('lower', a[0])?.toLowerCase(),
        minArgs: 1, maxArgs: 1),
    'trim': FunctionDefinition((a) => _str('trim', a[0])?.trim(),
        minArgs: 1, maxArgs: 1),
    'concat': FunctionDefinition((a) => a.map(formatValue).join()),

    // --- dates ---
    'today': FunctionDefinition((a) => today(), maxArgs: 0),
    'date':
        FunctionDefinition((a) => toDate('date', a[0]), minArgs: 1, maxArgs: 1),
    'age': FunctionDefinition(
      (a) {
        final birth = toDate('age', a[0]);
        if (birth == null) return null;
        return _wholeMonths(birth, today()) ~/ 12;
      },
      minArgs: 1,
      maxArgs: 1,
    ),
    'datediff': FunctionDefinition(
      (a) {
        final from = toDate('dateDiff', a[0]);
        final to = toDate('dateDiff', a[1]);
        if (from == null || to == null) return null;
        final unit = a.length > 2 ? _str('dateDiff', a[2]) ?? 'days' : 'days';
        return _dateDiff(from, to, unit.toLowerCase());
      },
      minArgs: 2,
      maxArgs: 3,
    ),
    'adddays': FunctionDefinition(
      (a) {
        final d = toDate('addDays', a[0]);
        if (d == null) return null;
        final n = _int('addDays', a[1]);
        return d.isUtc
            ? DateTime.utc(d.year, d.month, d.day + n, d.hour, d.minute,
                d.second, d.millisecond, d.microsecond)
            : DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second,
                d.millisecond, d.microsecond);
      },
      minArgs: 2,
      maxArgs: 2,
    ),
  };
}
