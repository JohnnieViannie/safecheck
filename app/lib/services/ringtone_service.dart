import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Central control for check-in call ring audio (phone ringtone, not alarm siren).
class RingtoneService {
  RingtoneService._();

  static final RingtoneService instance = RingtoneService._();

  static Future<void> startRinging() async {
    try {
      await FlutterRingtonePlayer().playRingtone(
        volume: 1.0,
        looping: true,
        asAlarm: false,
      );
    } catch (_) {
      // Plugin may be unavailable in some isolates; UI still shows.
    }
  }

  static Future<void> stopAll() async {
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {
      // Ignore stop failures.
    }
  }
}
