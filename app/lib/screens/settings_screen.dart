import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/screens/change_pin_screen.dart';
import 'package:safecheck/screens/document_vault_screen.dart';
import 'package:safecheck/screens/grace_period_settings_screen.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/biometric_service.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/widgets/grace_period_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);

  bool _loading = true;
  String _checkinTime = '18:00';
  String _frequency = 'Daily';
  int _graceMinutes = 120;
  bool _pinSet = false;
  String _fullName = '';

  bool _dailyReminder = true;
  bool _confirmationSms = true;
  bool _offlineAlerts = true;
  bool _biometricUnlock = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await _loadLocalDefaults();
    } catch (_) {
      // Show settings with defaults if local reads fail.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    unawaited(_refreshFromServer());
  }

  Future<void> _loadLocalDefaults() async {
    try {
      _biometricUnlock = await BiometricService.instance.isEnabled();
    } catch (_) {
      _biometricUnlock = false;
    }

    final UserModel? user = AuthService.instance.currentUser;
    if (user != null) {
      _fullName = user.firstName;
      _applyProfileFromUser(user, fallbackName: user.firstName);
    }

    try {
      final String? localTime = await StorageService.instance.getCheckinTime();
      if (localTime != null && localTime.trim().isNotEmpty) {
        _checkinTime = localTime.trim();
      }
      _frequency = await StorageService.instance.getCheckinFrequency();
      final Duration grace = await StorageService.instance.getGracePeriod();
      _graceMinutes = grace.inMinutes.clamp(15, 1440);
    } catch (_) {
      // Keep defaults.
    }

    if (user == null) {
      return;
    }

    try {
      final Map<String, dynamic>? cached =
          await StorageService.instance.getCachedProfile();
      if (cached != null) {
        _applyProfileFromUser(
          UserModel.fromMap(<String, dynamic>{...cached, 'uid': user.uid}),
          fallbackName: user.firstName,
        );
      }
    } catch (_) {
      // Keep values from session/local storage.
    }
  }

  Future<void> _refreshFromServer() async {
    final UserModel? user = AuthService.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final UserModel? profile = await AuthService.instance
          .getUserProfile(user.uid)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (profile != null && mounted) {
        setState(() {
          _applyProfileFromUser(profile, fallbackName: user.firstName);
        });
      }
    } catch (_) {
      // Cached/local values already shown.
    }

    try {
      await NotificationService.instance
          .scheduleDailyReminder(
            enabled: _dailyReminder,
            checkinTimeHHmm: _checkinTime,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Reminder scheduling can fail on some devices; settings still usable.
    }
  }

  void _applyProfileFromUser(UserModel profile, {String? fallbackName}) {
    _checkinTime = profile.checkinTime ?? _checkinTime;
    _frequency = profile.checkinFrequency ?? _frequency;
    if (profile.gracePeriodMinutes != null && profile.gracePeriodMinutes! > 0) {
      _graceMinutes = profile.gracePeriodMinutes!.clamp(15, 1440);
    } else if (profile.gracePeriodHours != null) {
      _graceMinutes = (profile.gracePeriodHours! * 60).clamp(15, 1440);
    }
    _pinSet = profile.pinSet;
    final String? name = profile.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      _fullName = name;
    } else if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      _fullName = fallbackName.trim();
    }
    _applyNotificationPrefs(profile.notificationPrefsJson);
  }

  void _applyNotificationPrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      _dailyReminder = decoded['daily_reminder'] as bool? ?? true;
      _confirmationSms = decoded['confirmation_sms'] as bool? ?? true;
      _offlineAlerts = decoded['offline_alerts'] as bool? ?? true;
    } catch (_) {
      // Keep local defaults.
    }
  }

  Future<void> _saveNotificationPrefs() async {
    final String payload = jsonEncode(<String, dynamic>{
      'daily_reminder': _dailyReminder,
      'confirmation_sms': _confirmationSms,
      'offline_alerts': _offlineAlerts,
    });

    final user = AuthService.instance.currentUser;
    if (user != null) {
      await AuthService.instance.createOrUpdateUser(
        uid: user.uid,
        phoneNumber: user.phoneNumber ?? '',
        extra: <String, dynamic>{'notification_prefs_json': payload},
      );
    }

    await NotificationService.instance.scheduleDailyReminder(
      enabled: _dailyReminder,
      checkinTimeHHmm: _checkinTime,
    );
  }

  Future<void> _setBiometricUnlock(bool value) async {
    if (value) {
      final bool canUse = await BiometricService.instance.canUnlockApp();
      if (!canUse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up fingerprint or Face ID in your phone settings first.',
            ),
          ),
        );
        return;
      }
      final BiometricAuthResult auth = await BiometricService.instance.authenticate(
        reason: 'Enable biometric unlock for SafeCheck',
        biometricOnly: true,
      );
      if (!auth.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              auth.errorMessage ?? 'Biometric verification failed.',
            ),
          ),
        );
        return;
      }
    }

    await BiometricService.instance.setEnabled(value);
    if (value) {
      await AuthService.instance.syncBiometricLoginBackup();
      BiometricLockSession.markUnlocked();
    }
    if (!mounted) return;
    setState(() => _biometricUnlock = value);
  }

  Future<String> _deviceTimezone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> _saveProfile(Map<String, dynamic> extra) async {
    extra['timezone'] = await _deviceTimezone();
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Log in again.')),
      );
      return;
    }

    final bool ok = await AuthService.instance.createOrUpdateUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber ?? '',
      extra: extra,
    );
    if (ok) {
      await SafetyService.instance.logTimelineEvent(
        uid: user.uid,
        eventType: 'settings_updated',
        status: 'success',
        payload: <String, dynamic>{'fields': extra.keys.toList()},
      );
    }
    if (!mounted) return;
    final bool pendingSync = await OfflineSyncService.instance.hasPending();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? pendingSync
                  ? 'Saved locally — will sync when back online.'
                  : 'Settings saved'
              : 'Could not save, try again',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _changeCallTime() async {
    final List<String> parts = _checkinTime.split(':');
    final TimeOfDay now = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;
    final String time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => _checkinTime = time);
    await StorageService.instance.saveSchedule(
      checkinTime: _checkinTime,
      checkinFrequency: _frequency,
    );
    await _saveProfile(<String, dynamic>{'checkin_time': _checkinTime});
    await NotificationService.instance.scheduleDailyReminder(
      enabled: _dailyReminder,
      checkinTimeHHmm: _checkinTime,
    );
  }

  Future<void> _changeGraceWindow() async {
    final int? saved = await Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
        builder: (BuildContext context) => GracePeriodSettingsScreen(
          initialMinutes: _graceMinutes,
          checkinFrequency: _frequency,
        ),
      ),
    );
    if (saved == null) return;
    setState(() => _graceMinutes = saved);
  }

  Future<void> _changePin() async {
    final bool? changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ChangePinScreen(
          requireCurrentPin: _pinSet,
        ),
      ),
    );
    if (changed == true) {
      setState(() => _pinSet = true);
    }
  }

  String get _initials {
    final List<String> parts = _fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'SC';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get _displayName {
    if (_fullName.trim().isNotEmpty) {
      return _fullName.trim();
    }
    return AuthService.instance.currentUser?.firstName ?? 'SafeCheck user';
  }

  String get _checkinScheduleLabel {
    return '${_frequency == 'Weekly' ? 'Weekly' : 'Daily'} at ${_displayTime(_checkinTime)}';
  }

  String get _graceLabel {
    return '${GracePeriodPicker.formatGraceDuration(_graceMinutes)} after check-in time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                physics: const BouncingScrollPhysics(),
                children: <Widget>[
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildProfileCard(),
                  const SizedBox(height: 28),
                  _buildSectionLabel('CHECK-IN SCHEDULE'),
                  const SizedBox(height: 12),
                  _settingsCard(
                    children: <Widget>[
                      _navTile(
                        icon: Icons.schedule_rounded,
                        title: 'Check-In Time',
                        subtitle: _checkinScheduleLabel,
                        onTap: _changeCallTime,
                      ),
                      _divider(),
                      _navTile(
                        icon: Icons.notifications_none_rounded,
                        title: 'Grace Period',
                        subtitle: _graceLabel,
                        onTap: _changeGraceWindow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _buildSectionLabel('NOTIFICATIONS'),
                  const SizedBox(height: 12),
                  _settingsCard(
                    children: <Widget>[
                      _toggleTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Daily reminder',
                        subtitle: '30 min before check-in',
                        value: _dailyReminder,
                        onChanged: (bool value) async {
                          setState(() => _dailyReminder = value);
                          await _saveNotificationPrefs();
                        },
                      ),
                      _divider(),
                      _toggleTile(
                        icon: Icons.sms_outlined,
                        title: 'Confirmation SMS',
                        subtitle: 'When alert cancelled',
                        value: _confirmationSms,
                        onChanged: (bool value) async {
                          setState(() => _confirmationSms = value);
                          await _saveNotificationPrefs();
                        },
                      ),
                      _divider(),
                      _toggleTile(
                        icon: Icons.monitor_heart_outlined,
                        title: 'Offline mode alerts',
                        subtitle: 'SMS-only when no data',
                        value: _offlineAlerts,
                        onChanged: (bool value) async {
                          setState(() => _offlineAlerts = value);
                          await _saveNotificationPrefs();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _buildSectionLabel('SECURITY'),
                  const SizedBox(height: 12),
                  _settingsCard(
                    children: <Widget>[
                      _navTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Change cancel PIN',
                        subtitle: '4-digit alert cancel code',
                        onTap: _changePin,
                      ),
                      _divider(),
                      _toggleTile(
                        icon: Icons.shield_outlined,
                        title: 'Biometric unlock',
                        subtitle: 'Lock when you return from background',
                        value: _biometricUnlock,
                        onChanged: (bool value) async {
                          await _setBiometricUnlock(value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _buildSectionLabel('DOCUMENTS'),
                  const SizedBox(height: 12),
                  _settingsCard(
                    children: <Widget>[
                      _navTile(
                        icon: Icons.description_outlined,
                        title: 'Document vault',
                        subtitle: 'Manage stored emergency documents',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DocumentVaultScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: const Text(
            'PRO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showProfileSheet,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: <Widget>[
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SafeCheck Pro · Active',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _accent.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.28),
          ),
        ],
      ),
        ),
      ),
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _displayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AuthService.instance.currentUser?.email ??
                    AuthService.instance.currentUser?.phoneNumber ??
                    'Signed in',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
              ),
              const SizedBox(height: 12),
              Text(
                'SafeCheck Pro · Active',
                style: TextStyle(
                  color: _accent.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: _accent.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 68,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              _iconBadge(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.48),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          _iconBadge(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: _accent.withValues(alpha: 0.45),
            activeThumbColor: _accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _iconBadge(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _accent, size: 20),
    );
  }

  String _displayTime(String hhmm) {
    final List<String> parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final int hour = int.tryParse(parts[0]) ?? 18;
    final int minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }
}
