/// Stable Android AlarmManager ids — keep in sync across scheduler + background.
class AlarmIds {
  AlarmIds._();

  static const int snooze = 1;

  /// Follow-up rings within grace period (ids 50–59).
  static const int retryBase = 50;
  static const int retrySlots = 10;
  static const Duration retryInterval = Duration(minutes: 5);

  /// Rebuilds alarm chain if OEM cleared alarms.
  static const int heartbeat = 99;
  static const Duration heartbeatInterval = Duration(hours: 6);

  /// Rolling future check-ins (100+).
  static const int rollingBase = 100;
  static const int dailyHorizon = 14;
  static const int weeklyHorizon = 4;

  static bool isRetry(int alarmId) =>
      alarmId >= retryBase && alarmId < retryBase + retrySlots;

  static bool isRolling(int alarmId) =>
      alarmId >= rollingBase &&
      alarmId < rollingBase + dailyHorizon;

  static bool isHeartbeat(int alarmId) => alarmId == heartbeat;

  static bool isSnooze(int alarmId) => alarmId == snooze;

  static bool shouldRing(int alarmId) =>
      isRolling(alarmId) || isRetry(alarmId) || isSnooze(alarmId);

  static int horizonForFrequency(String frequency) =>
      frequency == 'Weekly' ? weeklyHorizon : dailyHorizon;

  static Iterable<int> allManagedIds(String frequency) sync* {
    yield snooze;
    yield heartbeat;
    for (int i = 0; i < retrySlots; i++) {
      yield retryBase + i;
    }
    final int horizon = horizonForFrequency(frequency);
    for (int i = 0; i < horizon; i++) {
      yield rollingBase + i;
    }
  }
}
