import 'dart:convert';

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
  static const String _onboardingDraftKey = 'safecheck_onboarding_draft';
  static const String _cachedProfileKey = 'safecheck_cached_profile';
  static const String _cachedCheckinsKey = 'safecheck_cached_checkins';
  static const String _journeyModeActiveKey = 'safecheck_journey_mode_active';
  static const String _journeyModeStartedKey = 'safecheck_journey_mode_started_ms';
  static const String _journeySessionKey = 'safecheck_journey_session_json';
  static const String _scheduledAlarmIdsKey = 'safecheck_scheduled_alarm_ids';

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

  Future<void> saveOnboardingDraft(Map<String, dynamic> draft) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_onboardingDraftKey, jsonEncode(draft));
  }

  Future<Map<String, dynamic>?> getOnboardingDraft() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_onboardingDraftKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore corrupt draft
    }
    return null;
  }

  Future<void> clearOnboardingDraft() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingDraftKey);
  }

  Future<void> saveCachedProfile(Map<String, dynamic> profile) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedProfileKey, jsonEncode(profile));
  }

  Future<Map<String, dynamic>?> getCachedProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_cachedProfileKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore corrupt cache
    }
    return null;
  }

  Future<void> saveCachedCheckins(List<Map<String, dynamic>> checkins) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedCheckinsKey, jsonEncode(checkins));
  }

  Future<List<Map<String, dynamic>>?> getCachedCheckins() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_cachedCheckinsKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {
      // ignore corrupt cache
    }
    return null;
  }

  Future<void> setJourneyModeActive(
    bool active, {
    DateTime? startedAt,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_journeyModeActiveKey, active);
    if (active && startedAt != null) {
      await prefs.setInt(
        _journeyModeStartedKey,
        startedAt.millisecondsSinceEpoch,
      );
    } else if (!active) {
      await prefs.remove(_journeyModeStartedKey);
      await prefs.remove(_journeySessionKey);
    }
  }

  Future<void> saveJourneySession(Map<String, dynamic> session) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_journeySessionKey, jsonEncode(session));
  }

  Future<Map<String, dynamic>?> getJourneySession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_journeySessionKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore corrupt cache
    }
    return null;
  }

  Future<void> clearJourneySession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_journeySessionKey);
  }

  Future<bool> isJourneyModeActive() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_journeyModeActiveKey) ?? false;
  }

  Future<DateTime?> getJourneyModeStartedAt() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? raw = prefs.getInt(_journeyModeStartedKey);
    if (raw == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<Set<int>> getScheduledAlarmIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_scheduledAlarmIdsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <int>{};
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((dynamic id) => id as int).toSet();
      }
    } catch (_) {
      // ignore corrupt cache
    }
    return <int>{};
  }

  Future<void> saveScheduledAlarmIds(Set<int> ids) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduledAlarmIdsKey, jsonEncode(ids.toList()));
  }

  Future<void> addScheduledAlarmId(int id) async {
    final Set<int> ids = await getScheduledAlarmIds();
    ids.add(id);
    await saveScheduledAlarmIds(ids);
  }

  Future<void> removeScheduledAlarmId(int id) async {
    final Set<int> ids = await getScheduledAlarmIds();
    if (ids.remove(id)) {
      await saveScheduledAlarmIds(ids);
    }
  }

  Future<void> clearScheduledAlarmIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scheduledAlarmIdsKey);
  }
}
