import 'package:flutter/material.dart';

enum CheckinDayStatus { onTime, late, missed, pending, none }

class CheckinLogEntry {
  const CheckinLogEntry({
    required this.when,
    required this.status,
    required this.detail,
    required this.progress,
  });

  final DateTime when;
  final CheckinDayStatus status;
  final String detail;
  final double progress;
}

class CheckinHistory {
  CheckinHistory({
    required this.checkinTime,
    required this.gracePeriod,
  });

  final String checkinTime;
  final Duration gracePeriod;

  DateTime? parseWhen(Map<String, dynamic> checkin) {
    final dynamic raw = checkin['created_at'] ??
        checkin['createdAt'] ??
        checkin['timestamp'] ??
        checkin['at'];
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  DateTime scheduledForDay(DateTime day) {
    final List<String> parts = checkinTime.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  bool isLate(DateTime when) => when.isAfter(scheduledForDay(when));

  int graceMinutesUsed(DateTime when) {
    final DateTime scheduled = scheduledForDay(when);
    return when.difference(scheduled).inMinutes.clamp(0, gracePeriod.inMinutes);
  }

  int minutesEarly(DateTime when) {
    final DateTime scheduled = scheduledForDay(when);
    return scheduled.difference(when).inMinutes;
  }

  CheckinDayStatus statusForWhen(DateTime when) {
    if (isLate(when)) {
      return CheckinDayStatus.late;
    }
    return CheckinDayStatus.onTime;
  }

  String formatLogHeading(DateTime when) {
    const List<String> weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[when.weekday - 1]}, ${months[when.month - 1]} ${when.day}';
  }

  String formatClock(DateTime when, BuildContext context) {
    return TimeOfDay.fromDateTime(when).format(context);
  }

  String detailForCheckin(DateTime when, BuildContext context) {
    final String clock = formatClock(when, context);
    if (isLate(when)) {
      return 'Checked in at $clock · ${graceMinutesUsed(when)} min grace used';
    }
    final int early = minutesEarly(when);
    if (early >= 2) {
      return 'Checked in at $clock · $early min early';
    }
    return 'Checked in at $clock · On time';
  }

  double progressForStatus(CheckinDayStatus status) {
    switch (status) {
      case CheckinDayStatus.onTime:
        return 1;
      case CheckinDayStatus.late:
        return 0.72;
      case CheckinDayStatus.missed:
        return 1;
      case CheckinDayStatus.pending:
      case CheckinDayStatus.none:
        return 0;
    }
  }

  List<CheckinLogEntry> buildLogEntries(
    List<Map<String, dynamic>> checkins,
    BuildContext context,
  ) {
    final List<CheckinLogEntry> entries = <CheckinLogEntry>[];
    for (final Map<String, dynamic> checkin in checkins) {
      final DateTime? when = parseWhen(checkin);
      if (when == null) {
        continue;
      }
      final CheckinDayStatus status = statusForWhen(when);
      entries.add(
        CheckinLogEntry(
          when: when,
          status: status,
          detail: detailForCheckin(when, context),
          progress: progressForStatus(status),
        ),
      );
    }
    entries.sort((CheckinLogEntry a, CheckinLogEntry b) => b.when.compareTo(a.when));
    return entries;
  }

  List<CheckinDayStatus> buildWeekStatuses(
    List<Map<String, dynamic>> checkins,
    DateTime now,
  ) {
    final DateTime weekStart = now.subtract(Duration(days: now.weekday - 1));
    final Map<String, CheckinDayStatus> byDay = <String, CheckinDayStatus>{};

    for (final Map<String, dynamic> checkin in checkins) {
      final DateTime? when = parseWhen(checkin);
      if (when == null) {
        continue;
      }
      final String key = '${when.year}-${when.month}-${when.day}';
      byDay[key] = statusForWhen(when);
    }

    return List<CheckinDayStatus>.generate(7, (int index) {
      final DateTime day = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + index,
      );
      final String key = '${day.year}-${day.month}-${day.day}';
      if (byDay.containsKey(key)) {
        return byDay[key]!;
      }
      final DateTime endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
      if (endOfDay.isBefore(now.subtract(gracePeriod))) {
        return CheckinDayStatus.missed;
      }
      if (day.isAfter(DateTime(now.year, now.month, now.day))) {
        return CheckinDayStatus.none;
      }
      return CheckinDayStatus.pending;
    });
  }
}
