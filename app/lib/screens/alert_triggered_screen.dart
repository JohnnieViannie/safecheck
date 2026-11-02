import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safecheck/models/emergency_contact.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/widgets/pin_keypad_entry.dart';
import 'package:url_launcher/url_launcher.dart';

class AlertTriggeredScreen extends StatefulWidget {
  const AlertTriggeredScreen({
    super.key,
    required this.missedCheckinAt,
    this.triggeredAt,
  });

  final DateTime missedCheckinAt;
  final DateTime? triggeredAt;

  static Future<void> show(
    BuildContext context, {
    required DateTime missedCheckinAt,
    DateTime? triggeredAt,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AlertTriggeredScreen(
          missedCheckinAt: missedCheckinAt,
          triggeredAt: triggeredAt,
        ),
      ),
    );
  }

  @override
  State<AlertTriggeredScreen> createState() => _AlertTriggeredScreenState();
}

class _AlertTriggeredScreenState extends State<AlertTriggeredScreen> {
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _safeButton = Color(0xFF2F5D4E);

  String _firstName = 'You';
  String _checkinTimeLabel = '6:00 PM';
  String _contactsAlerted = 'Emergency contact';
  String _vaultReleased = 'Not released';
  double? _latitude;
  double? _longitude;
  bool _cancelling = false;

  DateTime get _triggeredAt => widget.triggeredAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    _firstName = AuthService.instance.currentUser?.firstName ?? 'You';

    final String? localTime = await StorageService.instance.getCheckinTime();
    if (localTime != null && localTime.trim().isNotEmpty) {
      _checkinTimeLabel = _formatScheduledTime(localTime.trim());
    }

    if (uid != null && uid.isNotEmpty) {
      try {
        final response = await ApiService.instance.get(
          '${Endpoints.userProfile}$uid/',
        );
        if (response.statusCode == 200) {
          final Map<String, dynamic> data =
              ApiService.instance.decodeJson<Map<String, dynamic>>(response);
          final profile = AuthService.instance.currentUser;
          if ((data['checkin_time'] as String? ?? '').trim().isNotEmpty) {
            _checkinTimeLabel =
                _formatScheduledTime(data['checkin_time'] as String);
          }
          final List<EmergencyContact> contacts =
              EmergencyContact.listFromProfile(data);
          if (contacts.isNotEmpty) {
            _contactsAlerted = _shortName(contacts.first.name);
          } else if ((profile?.emergencyContactName ?? '').trim().isNotEmpty) {
            _contactsAlerted = _shortName(profile!.emergencyContactName!);
          }
          _vaultReleased = _vaultLabelFromProfile(data);
        }
      } catch (_) {
        // Keep defaults.
      }
    }

    await _loadLocation();
    if (!mounted) return;
    setState(() {});
  }

  String _vaultLabelFromProfile(Map<String, dynamic> profile) {
    final dynamic raw = profile['trigger_actions_json'] ??
        profile['triggerActionsJson'];
    if (raw is! String || raw.trim().isEmpty) {
      return 'Not released';
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return 'Not released';
      }
      for (final dynamic item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String type = item['type']?.toString() ?? '';
        final bool enabled = item['enabled'] as bool? ?? true;
        if (type == 'document_vault' && enabled) {
          return 'Next-of-Kin';
        }
      }
    } catch (_) {
      return 'Not released';
    }
    return 'Not released';
  }

  Future<void> _loadLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      _latitude = position.latitude;
      _longitude = position.longitude;
    } catch (_) {
      // Map link stays disabled if location unavailable.
    }
  }

  String _shortName(String fullName) {
    final List<String> parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return fullName;
    }
    if (parts.length == 1) {
      return parts.first;
    }
    return '${parts.first} ${parts.last[0]}.';
  }

  String _formatScheduledTime(String hhmm) {
    final List<String> parts = hhmm.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final int hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final String minuteText = minute.toString().padLeft(2, '0');
    final String period = hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minuteText $period';
  }

  String _formatTriggeredTime(DateTime time) {
    final int hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String get _possessive {
    final String lower = _firstName.toLowerCase();
    if (lower == 'you' || lower == 'there') {
      return 'your';
    }
    return 'their';
  }

  String get _headline {
    if (_firstName.toLowerCase() == 'you' ||
        _firstName.toLowerCase() == 'there') {
      return 'You missed your $_checkinTimeLabel check-in.';
    }
    return '$_firstName missed $_possessive $_checkinTimeLabel check-in.';
  }

  Future<void> _openMap() async {
    if (_latitude == null || _longitude == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last location is not available yet.')),
      );
      return;
    }
    final Uri uri = Uri.parse(
      'https://maps.google.com/?q=$_latitude,$_longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _cancelAlert() async {
    if (_cancelling) return;

    final String? pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF112240),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => const _CancelAlertPinSheet(),
    );
    if (pin == null || pin.length != 4 || !mounted) {
      return;
    }

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }

    setState(() => _cancelling = true);
    await _performCancel(uid);
  }

  Future<void> _performCancel(String uid) async {
    HapticFeedback.heavyImpact();
    await StorageService.instance.saveLastCheckIn(DateTime.now());
    await SafetyService.instance.confirmSafe(uid: uid);
    await SafetyService.instance.createCheckin(
      uid: uid,
      status: 'safe_confirmed',
    );
    await SafetyService.instance.logTimelineEvent(
      uid: uid,
      eventType: 'alert_cancelled_after_trigger',
      status: 'safe_confirmed',
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _callEmergencyServices() async {
    final Uri uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF3A1420),
                Color(0xFF140D18),
                Color(0xFF0A192F),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: 12),
                          _buildWarningIcon(),
                          const SizedBox(height: 28),
                          const Text(
                            'Alert Triggered',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Georgia',
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '$_headline Your contacts have been alerted with your last known GPS location.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.58),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _buildDetailsCard(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _cancelling ? null : _cancelAlert,
                      style: FilledButton.styleFrom(
                        backgroundColor: _safeButton,
                        foregroundColor: const Color(0xFFBBF7D0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _cancelling ? 'Saving...' : 'I\'m okay — cancel alert',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _callEmergencyServices,
                      style: FilledButton.styleFrom(
                        backgroundColor: _danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Call emergency services',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarningIcon() {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _danger.withValues(alpha: 0.08),
        border: Border.all(color: _danger.withValues(alpha: 0.22), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _danger.withValues(alpha: 0.18),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(
        Icons.warning_amber_rounded,
        size: 52,
        color: _danger.withValues(alpha: 0.95),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          _detailRow('TIME TRIGGERED', _formatTriggeredTime(_triggeredAt)),
          _divider(),
          _detailRow(
            'LAST LOCATION',
            _latitude != null && _longitude != null
                ? 'View on map →'
                : 'Unavailable',
            valueColor: _latitude != null && _longitude != null ? _accent : null,
            onTap: _latitude != null && _longitude != null ? _openMap : null,
          ),
          _divider(),
          _detailRow('CONTACTS ALERTED', _contactsAlerted),
          _divider(),
          _detailRow('VAULT RELEASED', _vaultReleased),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final Widget valueWidget = Text(
      value,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: valueColor ?? Colors.white,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: onTap == null
                ? valueWidget
                : GestureDetector(
                    onTap: onTap,
                    child: valueWidget,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CancelAlertPinSheet extends StatefulWidget {
  const _CancelAlertPinSheet();

  @override
  State<_CancelAlertPinSheet> createState() => _CancelAlertPinSheetState();
}

class _CancelAlertPinSheetState extends State<_CancelAlertPinSheet> {
  final GlobalKey<PinKeypadEntryState> _pinKey = GlobalKey<PinKeypadEntryState>();
  String? _errorText;
  bool _verifying = false;

  Future<void> _onPinCompleted(String pin) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _errorText = null;
    });

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorText = 'Sign in required to verify PIN.';
      });
      _pinKey.currentState?.reset();
      return;
    }

    final profile = await AuthService.instance.getUserProfile(uid);
    if (profile == null || !profile.pinSet) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorText = 'No cancel PIN found on your profile.';
      });
      _pinKey.currentState?.reset();
      return;
    }

    final bool valid = await AuthService.instance.verifyPin(uid: uid, pin: pin);
    if (!mounted) return;
    if (!valid) {
      HapticFeedback.vibrate();
      setState(() {
        _verifying = false;
        _errorText = 'Incorrect PIN. Try again.';
      });
      _pinKey.currentState?.reset();
      return;
    }

    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter cancel PIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your 4-digit PIN to confirm you are cancelling this alert.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.52),
              ),
            ),
            PinKeypadEntry(
              key: _pinKey,
              enabled: !_verifying,
              errorText: _errorText,
              tipText:
                  'Only you should know this PIN. It stops alerts from reaching your contacts.',
              onChanged: () {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onCompleted: _onPinCompleted,
            ),
            if (_verifying) ...<Widget>[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PinKeypadEntry.accent,
                  ),
                ),
              ),
            ],
            TextButton(
              onPressed: _verifying ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Keep alert active',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
