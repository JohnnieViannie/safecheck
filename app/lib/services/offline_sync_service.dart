import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/utils/app_log.dart';

/// Queues API writes when offline and replays them when connectivity returns.
class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  static const String _queueKey = 'safecheck_offline_queue';

  static const String opEscalate = 'escalate';
  static const String opConfirmSafe = 'confirm_safe';
  static const String opCreateCheckin = 'create_checkin';
  static const String opSyncSnooze = 'sync_snooze';
  static const String opUpdateProfile = 'update_profile';
  static const String opVaultUpload = 'vault_upload';
  static const String opTimelineEvent = 'timeline_event';
  static const String opUpdateLocation = 'update_location';
  static const String opJourneyStart = 'journey_start';
  static const String opJourneyConfirm = 'journey_confirm';
  static const String opJourneyEnd = 'journey_end';
  static const String opJourneyPing = 'journey_ping';

  static const List<String> _priorityOrder = <String>[
    opEscalate,
    opConfirmSafe,
    opCreateCheckin,
    opJourneyEnd,
    opJourneyConfirm,
    opJourneyStart,
    opJourneyPing,
    opUpdateLocation,
    opSyncSnooze,
    opUpdateProfile,
    opVaultUpload,
    opTimelineEvent,
  ];

  bool _flushing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static bool isNetworkError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
  }

  Future<bool> hasPending() async {
    final List<Map<String, dynamic>> queue = await _loadQueue();
    return queue.isNotEmpty;
  }

  Future<int> pendingCount() async {
    final List<Map<String, dynamic>> queue = await _loadQueue();
    return queue.length;
  }

  void start() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool online = results.any(
          (ConnectivityResult result) => result != ConnectivityResult.none,
        );
        if (online) {
          unawaited(flush());
        }
      },
    );
    unawaited(flush());
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final List<Map<String, dynamic>> queue = await _loadQueue();
    queue.add(<String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _saveQueue(queue);
    appLog('[OfflineSync] queued $type (${queue.length} pending)');
  }

  Future<bool> flush() async {
    if (_flushing) {
      return false;
    }
    if (!await _isOnline()) {
      return false;
    }

    _flushing = true;
    try {
      _ensureAuth();
      List<Map<String, dynamic>> queue = await _loadQueue();
      if (queue.isEmpty) {
        return true;
      }

      queue.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final int ai = _priorityOrder.indexOf(a['type'] as String? ?? '');
        final int bi = _priorityOrder.indexOf(b['type'] as String? ?? '');
        return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
      });

      final List<Map<String, dynamic>> remaining = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> item in queue) {
        try {
          final bool ok = await _executeItem(item);
          if (!ok) {
            remaining.add(item);
          }
        } catch (error) {
          if (isNetworkError(error)) {
            remaining.add(item);
            break;
          }
          appLog('[OfflineSync] dropped ${item['type']}: $error');
        }
      }

      await _saveQueue(remaining);
      if (remaining.isEmpty && queue.isNotEmpty) {
        appLog('[OfflineSync] flush complete');
      }
      return remaining.isEmpty;
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _isOnline() async {
    try {
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();
      return results.any(
        (ConnectivityResult result) => result != ConnectivityResult.none,
      );
    } catch (_) {
      return true;
    }
  }

  Future<bool> _executeItem(Map<String, dynamic> item) async {
    final String type = item['type'] as String? ?? '';
    final Map<String, dynamic> payload =
        (item['payload'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

    switch (type) {
      case opEscalate:
        final http.Response response = await ApiService.instance.post(
          Endpoints.escalateMissed,
          body: <String, dynamic>{
            'uid': payload['uid'],
            'reason': payload['reason'] ?? 'missed_or_declined',
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opConfirmSafe:
        final http.Response response = await ApiService.instance.post(
          Endpoints.confirmSafe,
          body: <String, dynamic>{'uid': payload['uid']},
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opCreateCheckin:
        final http.Response response = await ApiService.instance.post(
          Endpoints.createCheckin,
          body: <String, dynamic>{
            'user_id': payload['uid'],
            'status': payload['status'] ?? 'ok',
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opSyncSnooze:
        final http.Response response = await ApiService.instance.post(
          Endpoints.snoozeCheckin,
          body: <String, dynamic>{
            'uid': payload['uid'],
            'snoozed_until': payload['snoozed_until'],
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opUpdateProfile:
        final http.Response response = await ApiService.instance.post(
          Endpoints.updateProfile,
          body: payload,
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }
        return false;

      case opVaultUpload:
        final String? localPath = payload['local_path'] as String?;
        if (localPath == null || localPath.isEmpty) {
          return true;
        }
        final File file = File(localPath);
        if (!await file.exists()) {
          return true;
        }
        final String filename =
            payload['filename'] as String? ?? file.uri.pathSegments.last;
        final http.MultipartFile multipart = await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: filename,
        );
        final http.Response response = await ApiService.instance.postMultipart(
          Endpoints.vaultUpload,
          fields: <String, String>{
            'uid': payload['uid'] as String,
            'title': payload['title'] as String? ?? 'Document',
            if (payload['slot_id'] != null)
              'slot_id': payload['slot_id'] as String,
          },
          file: multipart,
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opTimelineEvent:
        final http.Response response = await ApiService.instance.post(
          Endpoints.timelineEvents,
          body: <String, dynamic>{
            'uid': payload['uid'],
            'event_type': payload['event_type'],
            'source': payload['source'] ?? 'app',
            'status': payload['status'] ?? 'info',
            'payload_json': payload['payload_json'] ?? <String, dynamic>{},
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opUpdateLocation:
        final http.Response response = await ApiService.instance.post(
          Endpoints.updateLocation,
          body: <String, dynamic>{
            'uid': payload['uid'],
            'latitude': payload['latitude'],
            'longitude': payload['longitude'],
            if (payload['address'] != null) 'address': payload['address'],
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opJourneyStart:
        final http.Response response = await ApiService.instance.post(
          Endpoints.journeyStart,
          body: payload,
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opJourneyConfirm:
        final String journeyId = payload['journey_id'] as String;
        final http.Response response = await ApiService.instance.post(
          Endpoints.journeyConfirmArrival(journeyId),
          body: <String, dynamic>{
            'uid': payload['uid'],
            if (payload['latitude'] != null) 'latitude': payload['latitude'],
            if (payload['longitude'] != null) 'longitude': payload['longitude'],
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opJourneyEnd:
        final String journeyId = payload['journey_id'] as String;
        final http.Response response = await ApiService.instance.post(
          Endpoints.journeyEnd(journeyId),
          body: <String, dynamic>{
            'uid': payload['uid'],
            'reason': payload['reason'] ?? 'cancelled',
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      case opJourneyPing:
        final String journeyId = payload['journey_id'] as String;
        final http.Response response = await ApiService.instance.post(
          Endpoints.journeyPing(journeyId),
          body: <String, dynamic>{
            'uid': payload['uid'],
            'latitude': payload['latitude'],
            'longitude': payload['longitude'],
          },
        );
        return response.statusCode == 200 || response.statusCode == 201;

      default:
        return true;
    }
  }

  Future<void> cancelVaultUpload({
    String? docId,
    String? localPath,
  }) async {
    if ((docId == null || docId.isEmpty) &&
        (localPath == null || localPath.isEmpty)) {
      return;
    }

    final List<Map<String, dynamic>> queue = await _loadQueue();
    final List<Map<String, dynamic>> next = queue.where(
      (Map<String, dynamic> item) {
        if (item['type'] != opVaultUpload) {
          return true;
        }
        final Map<String, dynamic>? payload =
            (item['payload'] as Map?)?.cast<String, dynamic>();
        if (payload == null) {
          return true;
        }
        if (docId != null &&
            docId.isNotEmpty &&
            payload['slot_id']?.toString() == docId) {
          return false;
        }
        final String queuedPath = payload['local_path']?.toString() ?? '';
        if (localPath != null &&
            localPath.isNotEmpty &&
            queuedPath == localPath) {
          return false;
        }
        if (docId != null && docId.isNotEmpty && queuedPath.contains(docId)) {
          return false;
        }
        return true;
      },
    ).toList();

    if (next.length != queue.length) {
      await _saveQueue(next);
      appLog('[OfflineSync] cancelled pending vault upload for $docId');
    }
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_queueKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
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
      // ignore corrupt queue
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (queue.isEmpty) {
      await prefs.remove(_queueKey);
      return;
    }
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  /// Ensures bearer token is set before replaying queued writes.
  void _ensureAuth() {
    final String? token = AuthService.instance.token;
    if (token != null && token.isNotEmpty) {
      ApiService.instance.setBearerToken(token);
    }
  }
}
