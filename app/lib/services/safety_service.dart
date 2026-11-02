import 'package:http/http.dart' as http;
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/storage_service.dart';

class SafetyService {
  SafetyService._();

  static final SafetyService instance = SafetyService._();

  Future<bool> triggerCheckinCall(String uid) async {
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.triggerCall,
        body: <String, dynamic>{'uid': uid},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> escalateMissedOrDeclined({
    required String uid,
    String reason = 'missed_or_declined',
  }) async {
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.escalateMissed,
        body: <String, dynamic>{'uid': uid, 'reason': reason},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        return false;
      }
    }
    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opEscalate,
      payload: <String, dynamic>{'uid': uid, 'reason': reason},
    );
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchCallAttempts(String uid) async {
    try {
      final http.Response response = await ApiService.instance.get(
        '${Endpoints.callAttempts}/$uid/attempts/',
      );
      if (response.statusCode != 200) return <Map<String, dynamic>>[];
      final data = ApiService.instance.decodeJson<List<dynamic>>(response);
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAlerts(String uid) async {
    try {
      final http.Response response =
          await ApiService.instance.get('${Endpoints.alerts}/$uid/');
      if (response.statusCode != 200) return <Map<String, dynamic>>[];
      final data = ApiService.instance.decodeJson<List<dynamic>>(response);
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCheckins(String uid) async {
    try {
      final http.Response response =
          await ApiService.instance.get('${Endpoints.checkin}?uid=$uid');
      if (response.statusCode != 200) {
        return await _cachedCheckinsOrEmpty();
      }
      final data = ApiService.instance.decodeJson<List<dynamic>>(response);
      final List<Map<String, dynamic>> checkins =
          data.cast<Map<String, dynamic>>();
      await StorageService.instance.saveCachedCheckins(checkins);
      return checkins;
    } catch (_) {
      return await _cachedCheckinsOrEmpty();
    }
  }

  Future<List<Map<String, dynamic>>> _cachedCheckinsOrEmpty() async {
    return await StorageService.instance.getCachedCheckins() ??
        <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> fetchTimelineEvents(String uid) async {
    try {
      final http.Response response = await ApiService.instance.get(
        '${Endpoints.timelineEvents}?uid=$uid',
      );
      if (response.statusCode != 200) return <Map<String, dynamic>>[];
      final data = ApiService.instance.decodeJson<List<dynamic>>(response);
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<bool> createCheckin({
    required String uid,
    String status = 'ok',
  }) async {
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.createCheckin,
        body: <String, dynamic>{'user_id': uid, 'status': status},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        return false;
      }
    }
    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opCreateCheckin,
      payload: <String, dynamic>{'uid': uid, 'status': status},
    );
    return true;
  }

  Future<bool> confirmSafe({required String uid}) async {
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.confirmSafe,
        body: <String, dynamic>{'uid': uid},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        return false;
      }
    }
    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opConfirmSafe,
      payload: <String, dynamic>{'uid': uid},
    );
    return true;
  }

  Future<bool> syncSnooze({
    required String uid,
    required DateTime snoozedUntil,
  }) async {
    final String iso = snoozedUntil.toIso8601String();
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.snoozeCheckin,
        body: <String, dynamic>{
          'uid': uid,
          'snoozed_until': iso,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        return false;
      }
    }
    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opSyncSnooze,
      payload: <String, dynamic>{'uid': uid, 'snoozed_until': iso},
    );
    return true;
  }

  Future<bool> logTimelineEvent({
    required String uid,
    required String eventType,
    String source = 'app',
    String status = 'info',
    Map<String, dynamic>? payload,
  }) async {
    final Map<String, dynamic> payloadJson = payload ?? <String, dynamic>{};
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.timelineEvents,
        body: <String, dynamic>{
          'uid': uid,
          'event_type': eventType,
          'source': source,
          'status': status,
          'payload_json': payloadJson,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        return false;
      }
    }
    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opTimelineEvent,
      payload: <String, dynamic>{
        'uid': uid,
        'event_type': eventType,
        'source': source,
        'status': status,
        'payload_json': payloadJson,
      },
    );
    return true;
  }

  Future<bool> updateLocation({
    required String uid,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.updateLocation,
        body: <String, dynamic>{
          'uid': uid,
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opUpdateLocation,
          payload: <String, dynamic>{
            'uid': uid,
            'latitude': latitude,
            'longitude': longitude,
            if (address != null) 'address': address,
          },
        );
        return true;
      }
      return false;
    }
  }
}
