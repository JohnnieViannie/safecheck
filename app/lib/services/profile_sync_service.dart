import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/services/storage_service.dart';

/// Mirrors authoritative server profile fields into local device storage
/// (used only for alarms/offline alarm scheduling — server remains source of truth).
class ProfileSyncService {
  ProfileSyncService._();

  static final ProfileSyncService instance = ProfileSyncService._();

  Future<void> applyFromProfile(UserModel profile) async {
    if ((profile.checkinTime ?? '').trim().isNotEmpty) {
      await StorageService.instance.saveSchedule(
        checkinTime: profile.checkinTime!.trim(),
        checkinFrequency: profile.checkinFrequency ?? 'Daily',
      );
    }

    final Duration gracePeriod = _gracePeriod(profile);
    await StorageService.instance.savePeriodDurations(
      checkInPeriod: _checkInPeriod(profile.checkinFrequency),
      gracePeriod: gracePeriod,
    );

    if (profile.lastCheckInAt != null) {
      await StorageService.instance.saveLastCheckIn(profile.lastCheckInAt!);
    }

    if (profile.snoozedUntil != null &&
        profile.snoozedUntil!.isAfter(DateTime.now())) {
      await StorageService.instance.saveSnoozedUntil(profile.snoozedUntil!);
    } else {
      await StorageService.instance.clearSnoozedUntil();
    }
  }

  Duration _gracePeriod(UserModel profile) {
    if (profile.gracePeriodMinutes != null && profile.gracePeriodMinutes! > 0) {
      return Duration(minutes: profile.gracePeriodMinutes!);
    }
    final int hours = profile.gracePeriodHours ?? 2;
    return Duration(hours: hours.clamp(1, 24));
  }

  Duration _checkInPeriod(String? frequency) {
    final String normalized = (frequency ?? 'Daily').toLowerCase();
    if (normalized.contains('week')) {
      return const Duration(days: 7);
    }
    if (normalized.contains('hour')) {
      return const Duration(hours: 1);
    }
    return const Duration(days: 1);
  }
}
