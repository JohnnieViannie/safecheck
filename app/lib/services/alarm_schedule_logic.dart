/// Pure schedule math shared by foreground scheduler and background isolate.
class AlarmScheduleLogic {
  AlarmScheduleLogic._();

  static DateTime computeNextRegularAt({
    required DateTime now,
    required String checkinTime,
    required String frequency,
  }) {
    final List<String> parts = checkinTime.split(':');
    final int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

    final Duration period = frequency == 'Weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);

    DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(period);
    }
    return candidate;
  }

  static List<DateTime> rollingOccurrences({
    required DateTime now,
    required String checkinTime,
    required String frequency,
    required int horizon,
  }) {
    final Duration period = frequency == 'Weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);

    DateTime candidate = computeNextRegularAt(
      now: now,
      checkinTime: checkinTime,
      frequency: frequency,
    );

    final List<DateTime> result = <DateTime>[];
    for (int i = 0; i < horizon; i++) {
      result.add(candidate);
      candidate = candidate.add(period);
    }
    return result;
  }

  static List<DateTime> retryTimes({
    required DateTime firstRingAt,
    required Duration gracePeriod,
    required Duration retryInterval,
    required int maxSlots,
  }) {
    final List<DateTime> retries = <DateTime>[];
    DateTime next = firstRingAt.add(retryInterval);
    final DateTime deadline = firstRingAt.add(gracePeriod);

    for (int i = 0; i < maxSlots && next.isBefore(deadline); i++) {
      retries.add(next);
      next = next.add(retryInterval);
    }
    return retries;
  }
}
