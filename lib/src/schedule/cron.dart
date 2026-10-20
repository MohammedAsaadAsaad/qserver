/// Five-field cron (`minute hour day month weekday`). Seconds are ignored.
class CronExpression {
  final String source;
  final CronField _minute;
  final CronField _hour;
  final CronField _day;
  final CronField _month;
  final CronField _weekday;

  CronExpression._({
    required this.source,
    required CronField minute,
    required CronField hour,
    required CronField day,
    required CronField month,
    required CronField weekday,
  })  : _minute = minute,
        _hour = hour,
        _day = day,
        _month = month,
        _weekday = weekday;

  factory CronExpression.parse(String expression) {
    final parts = expression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw ArgumentError(
        'Cron expression must have 5 fields (got ${parts.length}): $expression',
      );
    }
    return CronExpression._(
      source: expression.trim(),
      minute: CronField.parse(parts[0], 0, 59),
      hour: CronField.parse(parts[1], 0, 23),
      day: CronField.parse(parts[2], 1, 31),
      month: CronField.parse(parts[3], 1, 12),
      weekday: CronField.parse(parts[4], 0, 6),
    );
  }

  bool matches(DateTime dt) {
    final local = dt.toLocal();
    return _minute.contains(local.minute) &&
        _hour.contains(local.hour) &&
        _day.contains(local.day) &&
        _month.contains(local.month) &&
        _weekday.contains(local.weekday % 7);
  }

  DateTime nextAfter(DateTime from) {
    var cursor = DateTime(
      from.year,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ).add(const Duration(minutes: 1));
    for (var i = 0; i < 366 * 24 * 60; i++) {
      if (matches(cursor)) return cursor;
      cursor = cursor.add(const Duration(minutes: 1));
    }
    throw StateError('No matching time for cron "$source" within a year');
  }

  Duration delayUntilNext([DateTime? from]) {
    final now = from ?? DateTime.now();
    final next = nextAfter(now);
    final delay = next.difference(now);
    return delay.isNegative ? Duration.zero : delay;
  }
}

class CronField {
  final Set<int> values;

  CronField(this.values);

  bool contains(int value) => values.contains(value);

  factory CronField.parse(String raw, int min, int max) {
    final values = <int>{};
    for (final part in raw.split(',')) {
      final piece = part.trim();
      if (piece == '*') {
        values.addAll([for (var i = min; i <= max; i++) i]);
        continue;
      }
      if (piece.startsWith('*/')) {
        final step = int.tryParse(piece.substring(2));
        if (step == null || step <= 0) {
          throw ArgumentError('Invalid cron step: $piece');
        }
        for (var i = min; i <= max; i += step) {
          values.add(i);
        }
        continue;
      }
      final range = piece.split('-');
      if (range.length == 2) {
        final start = int.tryParse(range[0]);
        final end = int.tryParse(range[1]);
        if (start == null || end == null || start < min || end > max) {
          throw ArgumentError('Invalid cron range: $piece');
        }
        for (var i = start; i <= end; i++) {
          values.add(i);
        }
        continue;
      }
      final n = int.tryParse(piece);
      if (n == null || n < min || n > max) {
        throw ArgumentError('Invalid cron value: $piece');
      }
      values.add(n);
    }
    return CronField(values);
  }
}
