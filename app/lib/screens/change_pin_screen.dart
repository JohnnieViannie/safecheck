import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/widgets/pin_keypad_entry.dart';

enum _ChangePinStep { verifyCurrent, enterNew, confirmNew }

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, this.requireCurrentPin = false});

  final bool requireCurrentPin;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  static const Color _background = Color(0xFF0A192F);

  final GlobalKey<PinKeypadEntryState> _keypadKey =
      GlobalKey<PinKeypadEntryState>();

  _ChangePinStep _step = _ChangePinStep.enterNew;
  String? _newPin;
  String? _errorText;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _step = widget.requireCurrentPin
        ? _ChangePinStep.verifyCurrent
        : _ChangePinStep.enterNew;
  }

  String get _title {
    switch (_step) {
      case _ChangePinStep.verifyCurrent:
        return 'Enter current PIN';
      case _ChangePinStep.enterNew:
        return 'Choose cancel PIN';
      case _ChangePinStep.confirmNew:
        return 'Confirm cancel PIN';
    }
  }

  String get _tipText {
    switch (_step) {
      case _ChangePinStep.verifyCurrent:
        return 'Enter your current 4-digit cancel PIN to continue.';
      case _ChangePinStep.enterNew:
        return 'Choose something memorable under pressure — like a birthday or favourite number. You can change it anytime in Settings.';
      case _ChangePinStep.confirmNew:
        return 'Must match the PIN you just entered. You\'ll use this to cancel alerts from notifications.';
    }
  }

  void _clearError() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  Future<void> _handleCompleted(String pin) async {
    if (_busy) return;

    switch (_step) {
      case _ChangePinStep.verifyCurrent:
        await _verifyCurrentPin(pin);
      case _ChangePinStep.enterNew:
        setState(() {
          _newPin = pin;
          _step = _ChangePinStep.confirmNew;
          _errorText = null;
        });
        _keypadKey.currentState?.reset();
      case _ChangePinStep.confirmNew:
        if (_newPin != pin) {
          HapticFeedback.vibrate();
          setState(() {
            _errorText = 'PINs do not match. Try again.';
            _step = _ChangePinStep.enterNew;
            _newPin = null;
          });
          _keypadKey.currentState?.reset();
          return;
        }
        await _savePin(pin);
    }
  }

  Future<void> _verifyCurrentPin(String pin) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Log in again.')),
      );
      return;
    }

    setState(() => _busy = true);
    final bool valid = await AuthService.instance.verifyPin(
      uid: user.uid,
      pin: pin,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!valid) {
      HapticFeedback.vibrate();
      setState(() => _errorText = 'Incorrect PIN. Try again.');
      _keypadKey.currentState?.reset();
      return;
    }

    setState(() {
      _step = _ChangePinStep.enterNew;
      _errorText = null;
    });
    _keypadKey.currentState?.reset();
  }

  Future<void> _savePin(String pin) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Log in again.')),
      );
      return;
    }

    setState(() => _busy = true);
    final bool ok = await AuthService.instance.createOrUpdateUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber ?? '',
      extra: <String, dynamic>{'pin': pin},
    );

    if (ok) {
      await SafetyService.instance.logTimelineEvent(
        uid: user.uid,
        eventType: 'settings_updated',
        status: 'success',
        payload: <String, dynamic>{'fields': <String>['pin']},
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      HapticFeedback.heavyImpact();
      final bool pendingSync = await OfflineSyncService.instance.hasPending();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendingSync
                ? 'PIN saved locally — will sync when back online.'
                : 'Cancel PIN updated',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _errorText = 'Could not save PIN. Try again.');
      _keypadKey.currentState?.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Text(_title),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PinKeypadEntry(
                key: _keypadKey,
                tipText: _tipText,
                enabled: !_busy,
                errorText: _errorText,
                onChanged: _clearError,
                onCompleted: _handleCompleted,
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x44000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
