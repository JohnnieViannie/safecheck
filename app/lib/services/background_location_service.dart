import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort location ping so escalation SMS has fresh coordinates.
class BackgroundLocationService {
  BackgroundLocationService._();

  static final BackgroundLocationService instance = BackgroundLocationService._();

  static const String _lastPingMsKey = 'last_location_ping_ms';
  static const Duration pingInterval = Duration(hours: 6);

  Future<void> pingIfDue() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int? lastMs = prefs.getInt(_lastPingMsKey);
    if (lastMs != null && nowMs - lastMs < pingInterval.inMilliseconds) {
      return;
    }

    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final bool ok = await SafetyService.instance.updateLocation(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (ok) {
        await prefs.setInt(_lastPingMsKey, nowMs);
      }
    } catch (_) {
      // Location is best-effort only.
    }
  }
}
