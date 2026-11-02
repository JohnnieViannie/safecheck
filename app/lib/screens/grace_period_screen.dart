import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/ringtone_service.dart';

class GracePeriodScreen extends StatefulWidget {
  const GracePeriodScreen({
    super.key,
    required this.scheduledFor,
    required this.gracePeriod,
  });

  final DateTime scheduledFor;
  final Duration gracePeriod;

  @override
  State<GracePeriodScreen> createState() => _GracePeriodScreenState();
}

class _GracePeriodScreenState extends State<GracePeriodScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF1A2332);
  static const Color _amber = Color(0xFFC9A86C);
  static const Color _keypadBackground = Color(0xFF112240);

  Timer? _timer;
  DateTime _now = DateTime.now();
  String _pin = '';
  bool _closing = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(RingtoneService.startRinging());
    HapticFeedback.mediumImpact();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _now = DateTime.now());
    if (_remaining <= Duration.zero && !_closing) {
      unawaited(_finish(
        const SimulatedCallResult(
          action: SimulatedCallAction.declined,
          note: 'grace_expired',
        ),
      ));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(RingtoneService.stopAll());
    unawaited(NotificationService.instance.cancelIncomingCheckinCall());
    super.dispose();
  }

  DateTime get _alertAt => widget.scheduledFor.add(widget.gracePeriod);

  Duration get _remaining {
    final Duration diff = _alertAt.difference(_now);
    if (diff.isNegative) {
      return Duration.zero;
    }
    return diff;
  }

  Future<void> _finish(SimulatedCallResult result) async {
    if (_closing) return;
    _closing = true;
    await RingtoneService.stopAll();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _confirmSafe() async {
    HapticFeedback.heavyImpact();
    await _finish(
      const SimulatedCallResult(action: SimulatedCallAction.safeConfirmed),
    );
  }

  Future<void> _needHelp() async {
    HapticFeedback.lightImpact();
    await _finish(
      const SimulatedCallResult(
        action: SimulatedCallAction.declined,
        note: 'need_help',
      ),
    );
  }

  void _appendDigit(String digit) {
    if (_pin.length >= 4 || _closing) return;
    setState(() {
      _pin += digit;
      _pinError = null;
    });
    if (_pin.length == 4) {
      unawaited(_submitPin());
    }
  }

  void _backspacePin() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _pinError = null;
    });
  }

  Future<void> _submitPin() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _pinError = 'Sign in required to verify PIN.');
      return;
    }

    final profile = await AuthService.instance.getUserProfile(uid);
    if (profile == null || !profile.pinSet) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _pinError = 'No cancel PIN found on your profile.';
      });
      return;
    }

    final bool valid = await AuthService.instance.verifyPin(
      uid: uid,
      pin: _pin,
    );
    if (!valid) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      setState(() {
        _pin = '';
        _pinError = 'Incorrect PIN. Try again.';
      });
      return;
    }

    HapticFeedback.heavyImpact();
    await _finish(
      const SimulatedCallResult(
        action: SimulatedCallAction.declined,
        note: 'cancelled_by_pin',
      ),
    );
  }

  String _formatCountdown(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatAlertTime(DateTime time) {
    final int hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _background,
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildAlertCard(),
                        const SizedBox(height: 24),
                        Text(
                          'Enter your 4-digit cancel PIN to stop the alert',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.52),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPinDots(),
                        if (_pinError != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            _pinError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF87171),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildNumericKeypad(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        const Text(
          'SafeCheck',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _amber.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: _amber.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              Text(
                'GRACE PERIOD',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: _amber.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'ALERT FIRES IN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _amber.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formatCountdown(_remaining),
            style: TextStyle(
              fontSize: 52,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _amber.withValues(alpha: 0.98),
            ),
          ),
          const SizedBox(height: 12),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.55),
              ),
              children: <TextSpan>[
                const TextSpan(text: 'Your contacts will be alerted at '),
                TextSpan(
                  text: _formatAlertTime(_alertAt),
                  style: TextStyle(
                    color: _amber.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _confirmSafe,
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: const Color(0xFF0A192F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'I\'m okay — check in',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _needHelp,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Need help',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (int index) {
        final bool filled = index < _pin.length;
        return Container(
          width: 14,
          height: 14,
          margin: EdgeInsets.only(left: index == 0 ? 0 : 14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? _amber : Colors.transparent,
            border: Border.all(
              color: filled
                  ? _amber
                  : Colors.white.withValues(alpha: 0.28),
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNumericKeypad() {
    Widget digitButton(int digit) {
      return _keypadButton(
        onTap: () => _appendDigit('$digit'),
        child: Text(
          '$digit',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      );
    }

    Widget keypadRow(List<Widget> buttons) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < buttons.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              buttons[i],
            ],
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        keypadRow(<Widget>[digitButton(1), digitButton(2), digitButton(3)]),
        keypadRow(<Widget>[digitButton(4), digitButton(5), digitButton(6)]),
        keypadRow(<Widget>[digitButton(7), digitButton(8), digitButton(9)]),
        keypadRow(<Widget>[
          _keypadButton(
            onTap: () => setState(() {
              _pin = '';
              _pinError = null;
            }),
            child: Text(
              'Clear',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
          digitButton(0),
          _keypadButton(
            onTap: _backspacePin,
            child: Icon(
              Icons.backspace_outlined,
              size: 22,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _keypadButton({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              color: _keypadBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
