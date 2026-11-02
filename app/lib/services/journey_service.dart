import 'package:http/http.dart' as http;
import 'package:safecheck/models/journey_session.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/storage_service.dart';

class JourneyService {
  JourneyService._();

  static final JourneyService instance = JourneyService._();

  String? lastStartError;

  Future<JourneySessionData?> fetchActive(String uid) async {
    try {
      final http.Response response = await ApiService.instance.get(
        '${Endpoints.journeyActive}?uid=$uid',
      );
      if (response.statusCode != 200) {
        return await _loadCached();
      }
      final Map<String, dynamic> data =
          ApiService.instance.decodeJson<Map<String, dynamic>>(response);
      if (data['active'] != true) {
        await StorageService.instance.clearJourneySession();
        await StorageService.instance.setJourneyModeActive(false);
        return null;
      }
      final Map<String, dynamic>? journey =
          data['journey'] as Map<String, dynamic>?;
      if (journey == null) {
        return null;
      }
      final JourneySessionData session = JourneySessionData.fromJson(journey);
      await StorageService.instance.saveJourneySession(session.toJson());
      await StorageService.instance.setJourneyModeActive(
        true,
        startedAt: session.startedAt,
      );
      return session;
    } catch (_) {
      return await _loadCached();
    }
  }

  Future<JourneySessionData?> _loadCached() async {
    final Map<String, dynamic>? cached =
        await StorageService.instance.getJourneySession();
    if (cached == null) {
      return null;
    }
    final JourneySessionData session = JourneySessionData.fromJson(cached);
    return session.isActive ? session : null;
  }

  Future<JourneySessionData?> startJourney({
    required String uid,
    required String fromLocation,
    required String toLocation,
    required int durationMinutes,
    required String checkinFrequency,
    double? latitude,
    double? longitude,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'uid': uid,
      'from_location': fromLocation,
      'to_location': toLocation,
      'duration_minutes': durationMinutes,
      'checkin_frequency': checkinFrequency,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

    lastStartError = null;

    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.journeyStart,
        body: body,
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        lastStartError = _readApiError(response);
        if (response.statusCode == 404) {
          lastStartError =
              'Server is still running old backend code (journeys/start/ not found). '
              'On the VPS: git pull, then restart gunicorn — migrate alone is not enough.';
        }
        return null;
      }
      final Map<String, dynamic> data =
          ApiService.instance.decodeJson<Map<String, dynamic>>(response);
      final JourneySessionData session = JourneySessionData.fromJson(data);
      await _persistSession(session);
      return session;
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        final JourneySessionData offlineSession = JourneySessionData(
          journeyId: 'offline-${DateTime.now().millisecondsSinceEpoch}',
          fromLocation: fromLocation,
          toLocation: toLocation,
          durationMinutes: durationMinutes,
          checkinFrequency: checkinFrequency,
          startedAt: DateTime.now(),
          expectedArrivalAt:
              DateTime.now().add(Duration(minutes: durationMinutes)),
          lastLatitude: latitude,
          lastLongitude: longitude,
        );
        await _persistSession(offlineSession);
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opJourneyStart,
          payload: body,
        );
        return offlineSession;
      }
      rethrow;
    }
  }

  Future<bool> confirmArrival({
    required String uid,
    required String journeyId,
    double? latitude,
    double? longitude,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'uid': uid,
      'journey_id': journeyId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.journeyConfirmArrival(journeyId),
        body: <String, dynamic>{
          'uid': uid,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _clearLocal();
        return true;
      }
      return false;
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opJourneyConfirm,
          payload: body,
        );
        await _clearLocal();
        return true;
      }
      return false;
    }
  }

  Future<bool> endJourney({
    required String uid,
    required String journeyId,
    String reason = 'cancelled',
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'uid': uid,
      'journey_id': journeyId,
      'reason': reason,
    };

    try {
      final http.Response response = await ApiService.instance.post(
        Endpoints.journeyEnd(journeyId),
        body: <String, dynamic>{'uid': uid, 'reason': reason},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _clearLocal();
        return true;
      }
      return false;
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opJourneyEnd,
          payload: body,
        );
        await _clearLocal();
        return true;
      }
      return false;
    }
  }

  Future<void> pingLocation({
    required String uid,
    required String journeyId,
    required double latitude,
    required double longitude,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'uid': uid,
      'journey_id': journeyId,
      'latitude': latitude,
      'longitude': longitude,
    };

    try {
      await ApiService.instance.post(
        Endpoints.journeyPing(journeyId),
        body: <String, dynamic>{
          'uid': uid,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opJourneyPing,
          payload: body,
        );
      }
    }
  }

  Future<bool> markMissedIfOverdue({
    required String uid,
    required JourneySessionData session,
  }) async {
    if (!session.isActive ||
        !DateTime.now().isAfter(session.expectedArrivalAt)) {
      return false;
    }
    if (session.journeyId.startsWith('offline-')) {
      return false;
    }
    return endJourney(
      uid: uid,
      journeyId: session.journeyId,
      reason: 'missed',
    );
  }

  Future<void> _persistSession(JourneySessionData session) async {
    await StorageService.instance.saveJourneySession(session.toJson());
    await StorageService.instance.setJourneyModeActive(
      true,
      startedAt: session.startedAt,
    );
  }

  Future<void> _clearLocal() async {
    await StorageService.instance.clearJourneySession();
    await StorageService.instance.setJourneyModeActive(false);
  }

  String? _readApiError(http.Response response) {
    try {
      final Map<String, dynamic> data =
          ApiService.instance.decodeJson<Map<String, dynamic>>(response);
      final Object? error = data['error'];
      if (error != null) {
        return error.toString();
      }
    } catch (_) {
      // ignore non-JSON error bodies
    }
    return 'Server error (${response.statusCode})';
  }
}
