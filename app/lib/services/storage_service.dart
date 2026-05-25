import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const String _lastCheckInKey = 'last_check_in';
  static const String _checkInPeriodMsKey = 'check_in_period_ms';
  static const String _gracePeriodMsKey = 'grace_period_ms';
  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _checkinTimeKey = 'checkin_time';
  static const String _checkinFrequencyKey = 'checkin_frequency';
  static const String _snoozedUntilKey = 'snoozed_until_ms';

  Future<void> saveLastCheckIn(DateTime value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckInKey, value.millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastCheckIn() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? timestamp = prefs.getInt(_lastCheckInKey);
    if (timestamp == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> savePeriodDurations({
    required Duration checkInPeriod,
    required Duration gracePeriod,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_checkInPeriodMsKey, checkInPeriod.inMilliseconds);
    await prefs.setInt(_gracePeriodMsKey, gracePeriod.inMilliseconds);
  }

  Future<void> saveSchedule({
    required String checkinTime,
    required String checkinFrequency,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checkinTimeKey, checkinTime);
    await prefs.setString(_checkinFrequencyKey, checkinFrequency);
  }

  Future<Duration> getCheckInPeriod() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int value =
        prefs.getInt(_checkInPeriodMsKey) ?? Duration(days: 1).inMilliseconds;
    return Duration(milliseconds: value);
  }

  Future<Duration> getGracePeriod() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int value =
        prefs.getInt(_gracePeriodMsKey) ?? Duration(hours: 2).inMilliseconds;
    return Duration(milliseconds: value);
  }

  Future<String?> getCheckinTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_checkinTimeKey);
  }

  Future<String> getCheckinFrequency() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_checkinFrequencyKey) ?? 'Daily';
  }

  Future<void> saveSnoozedUntil(DateTime value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozedUntilKey, value.millisecondsSinceEpoch);
  }

  Future<DateTime?> getSnoozedUntil() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? raw = prefs.getInt(_snoozedUntilKey);
    if (raw == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> clearSnoozedUntil() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snoozedUntilKey);
  }

  Future<void> saveApiBaseUrl(String url) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, url);
  }

  Future<String?> getApiBaseUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_apiBaseUrlKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}
