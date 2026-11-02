import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/ringtone_service.dart';
import 'package:safecheck/widgets/app_logo.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
    super.key,
    required this.contextData,
    required this.gracePeriod,
    this.snoozeDuration = const Duration(minutes: 30),
  });

  final SimulatedCallContext contextData;
  final Duration gracePeriod;
  final Duration snoozeDuration;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen>
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);

  late final AnimationController _pulseController;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      if (!_closing && !_now.isBefore(_alertAt)) {
        unawaited(_finish(
          const SimulatedCallResult(
            action: SimulatedCallAction.declined,
            note: 'grace_expired',
          ),
        ));
      }
    });
    unawaited(RingtoneService.startRinging());
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pulseController.dispose();
    unawaited(RingtoneService.stopAll());
    unawaited(NotificationService.instance.cancelIncomingCheckinCall());
    super.dispose();
  }

  DateTime get _alertAt =>
      widget.contextData.scheduledFor.add(widget.gracePeriod);

  double get _graceProgress {
    final Duration elapsed = _now.difference(widget.contextData.scheduledFor);
    if (elapsed.isNegative) return 0;
    if (widget.gracePeriod.inSeconds <= 0) return 1;
    return (elapsed.inSeconds / widget.gracePeriod.inSeconds).clamp(0.0, 1.0);
  }

  Future<void> _finish(SimulatedCallResult result) async {
    if (_closing) return;
    _closing = true;
    await RingtoneService.stopAll();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _confirmSafe() async {
    if (_closing) return;
    HapticFeedback.heavyImpact();
    await _finish(
      const SimulatedCallResult(action: SimulatedCallAction.safeConfirmed),
    );
  }

  Future<void> _snooze() async {
    if (_closing) return;
    HapticFeedback.lightImpact();
    await _finish(
      SimulatedCallResult(
        action: SimulatedCallAction.remindMe,
        snoozedUntil: DateTime.now().add(widget.snoozeDuration),
      ),
    );
  }

  Future<void> _needHelp() async {
    if (_closing) return;
    HapticFeedback.lightImpact();
    await _finish(
      const SimulatedCallResult(
        action: SimulatedCallAction.declined,
        note: 'need_help',
      ),
    );
  }

  Future<void> _promptCancelPin() async {
    final String? entered = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _CancelPinDialog(),
    );
    if (entered == null || entered.length != 4 || !mounted) return;

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required to verify PIN.')),
      );
      return;
    }

    final profile = await AuthService.instance.getUserProfile(uid);
    if (profile == null || !profile.pinSet) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cancel PIN found on your profile.')),
      );
      return;
    }

    final bool valid = await AuthService.instance.verifyPin(
      uid: uid,
      pin: entered,
    );
    if (!valid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN.')),
      );
      return;
    }

    if (_closing) return;
    HapticFeedback.heavyImpact();
    await _finish(
      const SimulatedCallResult(
        action: SimulatedCallAction.declined,
        note: 'cancelled_by_pin',
      ),
    );
  }

  String _formatClock(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime time) {
    const List<String> weekdays = <String>[
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const List<String> months = <String>[
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${weekdays[time.weekday - 1]}, ${months[time.month - 1]} ${time.day}';
  }

  String _formatGracePeriod(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return '$hours hr $minutes min';
    }
    if (hours > 0) {
      return hours == 1 ? '1 hr' : '$hours hrs';
    }
    return minutes == 1 ? '1 min' : '$minutes min';
  }

  String _formatAlertTime(DateTime time) {
    final int hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String get _snoozeLabel {
    final int minutes = widget.snoozeDuration.inMinutes;
    return 'Snooze $minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isCompact = screenHeight < 760;
    final bool isVeryCompact = screenHeight < 700;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _background,
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: <Widget>[
                        SizedBox(height: isVeryCompact ? 4 : (isCompact ? 8 : 16)),
                        _buildNotificationBanner(),
                        SizedBox(height: isVeryCompact ? 12 : (isCompact ? 16 : 28)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatClock(_now),
                            style: TextStyle(
                              fontSize: isVeryCompact ? 48 : (isCompact ? 56 : 72),
                              height: 1,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Georgia',
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(_now),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                        SizedBox(height: isVeryCompact ? 12 : (isCompact ? 16 : 24)),
                        _buildOkayButton(isCompact, isVeryCompact),
                        SizedBox(height: isVeryCompact ? 8 : 12),
                      ],
                    ),
                  ),
                ),
                _buildGraceStatus(),
                SizedBox(height: isVeryCompact ? 10 : 14),
                _buildProgressBar(),
                SizedBox(height: isVeryCompact ? 10 : 14),
                GestureDetector(
                  onTap: _promptCancelPin,
                  child: Text(
                    'Need to cancel an alert? Enter your PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                ),
                SizedBox(height: isVeryCompact ? 10 : 14),
                _buildSnoozeButton(),
                const SizedBox(height: 8),
                _buildNeedHelpButton(),
                SizedBox(height: isVeryCompact ? 8 : 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                AppLogo.darkAssetPath,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SAFECHECK · NOW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: _accent.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Time to check in. Tap to confirm you\'re okay.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOkayButton(bool isCompact, bool isVeryCompact) {
    final double size = isVeryCompact ? 156 : (isCompact ? 176 : 220);
    final double outerPadding = isVeryCompact ? 28 : (isCompact ? 36 : 48);
    final double iconSize = isVeryCompact ? 34 : (isCompact ? 38 : 42);
    final double titleSize = isVeryCompact ? 18 : (isCompact ? 20 : 22);

    return GestureDetector(
      onTap: _confirmSafe,
      child: SizedBox(
        width: size + outerPadding,
        height: size + outerPadding,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            for (int ring = 0; ring < 3; ring++)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (BuildContext context, Widget? child) {
                  final double phase = (_pulseController.value + ring * 0.22) % 1.0;
                  final double scale = 1.0 + (phase * 0.18) + (ring * 0.06);
                  final double opacity = (1.0 - phase) * (0.28 - ring * 0.06);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _accent.withValues(alpha: opacity.clamp(0.0, 1.0)),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    _accent.withValues(alpha: 0.95),
                    _accent.withValues(alpha: 0.78),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.35),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.shield_outlined,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  SizedBox(height: isVeryCompact ? 6 : 10),
                  Text(
                    'I\'M OKAY',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to confirm',
                    style: TextStyle(
                      fontSize: isVeryCompact ? 11 : 13,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraceStatus() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: Colors.white.withValues(alpha: 0.52),
        ),
        children: <TextSpan>[
          const TextSpan(text: 'Grace period: '),
          TextSpan(
            text: _formatGracePeriod(widget.gracePeriod),
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' · Alerts at '),
          TextSpan(
            text: _formatAlertTime(_alertAt),
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: _graceProgress,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation<Color>(_accent.withValues(alpha: 0.9)),
        ),
      ),
    );
  }

  Widget _buildSnoozeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: _snooze,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: _cardBackground,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _snoozeLabel,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildNeedHelpButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _needHelp,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.72),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
    );
  }
}

class _CancelPinDialog extends StatefulWidget {
  const _CancelPinDialog();

  @override
  State<_CancelPinDialog> createState() => _CancelPinDialogState();
}

class _CancelPinDialogState extends State<_CancelPinDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF112240),
      title: const Text(
        'Cancel alert',
        style: TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        autofocus: true,
        style: const TextStyle(color: Colors.white, letterSpacing: 8),
        decoration: InputDecoration(
          counterText: '',
          hintText: '••••',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF14B8A6)),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Back',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text(
            'Confirm',
            style: TextStyle(color: Color(0xFF14B8A6)),
          ),
        ),
      ],
    );
  }
}
