import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/endpoints.dart';

class SafetyService {
  SafetyService._();

  static final SafetyService instance = SafetyService._();

  Future<bool> triggerCheckinCall(String uid) async {
    final response = await ApiService.instance.post(
      Endpoints.triggerCall,
      body: <String, dynamic>{'uid': uid},
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> escalateMissedOrDeclined({
    required String uid,
    String reason = 'missed_or_declined',
  }) async {
    final response = await ApiService.instance.post(
      Endpoints.escalateMissed,
      body: <String, dynamic>{'uid': uid, 'reason': reason},
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Map<String, dynamic>>> fetchCallAttempts(String uid) async {
    final response = await ApiService.instance.get(
      '${Endpoints.callAttempts}/$uid/attempts/',
    );
    if (response.statusCode != 200) return <Map<String, dynamic>>[];
    final data = ApiService.instance.decodeJson<List<dynamic>>(response);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchAlerts(String uid) async {
    final response = await ApiService.instance.get('${Endpoints.alerts}/$uid/');
    if (response.statusCode != 200) return <Map<String, dynamic>>[];
    final data = ApiService.instance.decodeJson<List<dynamic>>(response);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchCheckins(String uid) async {
    final response = await ApiService.instance.get('${Endpoints.checkin}?uid=$uid');
    if (response.statusCode != 200) return <Map<String, dynamic>>[];
    final data = ApiService.instance.decodeJson<List<dynamic>>(response);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchTimelineEvents(String uid) async {
    final response = await ApiService.instance.get(
      '${Endpoints.timelineEvents}?uid=$uid',
    );
    if (response.statusCode != 200) return <Map<String, dynamic>>[];
    final data = ApiService.instance.decodeJson<List<dynamic>>(response);
    return data.cast<Map<String, dynamic>>();
  }

  Future<bool> createCheckin({
    required String uid,
    String status = 'ok',
  }) async {
    final response = await ApiService.instance.post(
      Endpoints.createCheckin,
      body: <String, dynamic>{'user_id': uid, 'status': status},
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> confirmSafe({required String uid}) async {
    final response = await ApiService.instance.post(
      Endpoints.confirmSafe,
      body: <String, dynamic>{'uid': uid},
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> syncSnooze({
    required String uid,
    required DateTime snoozedUntil,
  }) async {
    final response = await ApiService.instance.post(
      Endpoints.snoozeCheckin,
      body: <String, dynamic>{
        'uid': uid,
        'snoozed_until': snoozedUntil.toIso8601String(),
      },
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> logTimelineEvent({
    required String uid,
    required String eventType,
    String source = 'app',
    String status = 'info',
    Map<String, dynamic>? payload,
  }) async {
    final response = await ApiService.instance.post(
      Endpoints.timelineEvents,
      body: <String, dynamic>{
        'uid': uid,
        'event_type': eventType,
        'source': source,
        'status': status,
        'payload_json': payload ?? <String, dynamic>{},
      },
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateLocation({
    required String uid,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    final response = await ApiService.instance.post(
      Endpoints.updateLocation,
      body: <String, dynamic>{
        'uid': uid,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      },
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }
}
