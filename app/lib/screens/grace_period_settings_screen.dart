import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/widgets/grace_period_picker.dart';

class GracePeriodSettingsScreen extends StatefulWidget {
  const GracePeriodSettingsScreen({
    super.key,
    required this.initialMinutes,
    this.checkinFrequency = 'Daily',
  });

  final int initialMinutes;
  final String checkinFrequency;

  @override
  State<GracePeriodSettingsScreen> createState() =>
      _GracePeriodSettingsScreenState();
}

class _GracePeriodSettingsScreenState extends State<GracePeriodSettingsScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _accent = Color(0xFF14B8A6);

  late int _graceMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _graceMinutes = widget.initialMinutes.clamp(15, 1440);
  }

  Future<String> _deviceTimezone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Log in again.')),
      );
      return;
    }

    final int graceHours = (_graceMinutes / 60).ceil();
    final bool ok = await AuthService.instance.createOrUpdateUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber ?? '',
      extra: <String, dynamic>{
        'timezone': await _deviceTimezone(),
        'grace_period_hours': graceHours,
        'grace_period_minutes': _graceMinutes,
      },
    );

    if (ok) {
      await StorageService.instance.savePeriodDurations(
        checkInPeriod: widget.checkinFrequency == 'Weekly'
            ? const Duration(days: 7)
            : const Duration(days: 1),
        gracePeriod: Duration(minutes: _graceMinutes),
      );
      await SafetyService.instance.logTimelineEvent(
        uid: user.uid,
        eventType: 'settings_updated',
        status: 'success',
        payload: <String, dynamic>{
          'fields': <String>['grace_period_minutes', 'grace_period_hours'],
        },
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      final bool pendingSync = await OfflineSyncService.instance.hasPending();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendingSync
                ? 'Saved locally — will sync when back online.'
                : 'Grace period saved',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, _graceMinutes);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save, try again')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Grace period'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: GracePeriodPicker(
                  initialMinutes: _graceMinutes,
                  onChanged: (int minutes) {
                    setState(() => _graceMinutes = minutes);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save grace period'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
