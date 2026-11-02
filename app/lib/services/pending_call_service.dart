import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingCallPayload {
  const PendingCallPayload({
    required this.callKitId,
    required this.scheduledFor,
    required this.frequency,
    required this.checkinTime,
    required this.alarmId,
    required this.source,
  });

  final String callKitId;
  final DateTime scheduledFor;
  final String frequency;
  final String checkinTime;
  final int alarmId;
  final String source;

  bool get isSnoozedRetry => alarmId == 1;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'callKitId': callKitId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'frequency': frequency,
      'checkinTime': checkinTime,
      'alarmId': alarmId,
      'source': source,
    };
  }

  factory PendingCallPayload.fromJson(Map<String, dynamic> json) {
    return PendingCallPayload(
      callKitId: json['callKitId']?.toString() ?? '',
      scheduledFor: DateTime.tryParse(
            json['scheduledFor']?.toString() ?? '',
          ) ??
          DateTime.now(),
      frequency: json['frequency']?.toString() ?? 'Daily',
      checkinTime: json['checkinTime']?.toString() ?? '18:00',
      alarmId: int.tryParse(json['alarmId']?.toString() ?? '') ?? 0,
      source: json['source']?.toString() ?? 'local_alarm',
    );
  }
}

class PendingCallService {
  PendingCallService._();

  static final PendingCallService instance = PendingCallService._();

  static const String _storageKey = 'safecheck_pending_call';

  Future<void> save(PendingCallPayload payload) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(payload.toJson()));
  }

  Future<PendingCallPayload?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PendingCallPayload.fromJson(decoded);
      }
    } catch (_) {
      // ignore corrupt payload
    }
    return null;
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
