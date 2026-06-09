import 'package:shared_preferences/shared_preferences.dart';

/// Prevents duplicate incoming-call UI when local alarms and FCM fire together.
class CallDedupService {
  CallDedupService._();

  static final CallDedupService instance = CallDedupService._();

  static const String _lastRingMsKey = 'last_call_ring_ms';
  static const String _lastCallKitIdKey = 'last_call_kit_id';
  static const Duration dedupWindow = Duration(minutes: 3);

  Future<bool> shouldShowCall({
    required String callKitId,
    DateTime? scheduledFor,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    final String? lastId = prefs.getString(_lastCallKitIdKey);
    final int? lastMs = prefs.getInt(_lastRingMsKey);

    if (lastId != null &&
        lastId == callKitId &&
        lastMs != null &&
        nowMs - lastMs < dedupWindow.inMilliseconds) {
      return false;
    }

    if (scheduledFor != null && lastMs != null) {
      final int scheduledMs = scheduledFor.millisecondsSinceEpoch;
      if ((scheduledMs - lastMs).abs() < dedupWindow.inMilliseconds) {
        return false;
      }
    }

    await prefs.setString(_lastCallKitIdKey, callKitId);
    await prefs.setInt(_lastRingMsKey, nowMs);
    return true;
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCallKitIdKey);
    await prefs.remove(_lastRingMsKey);
  }
}
