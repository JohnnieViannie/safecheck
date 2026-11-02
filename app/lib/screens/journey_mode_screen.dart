import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safecheck/models/journey_session.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/journey_scheduler.dart';
import 'package:safecheck/services/journey_service.dart';
import 'package:safecheck/services/safety_service.dart';

class JourneyModeScreen extends StatefulWidget {
  const JourneyModeScreen({super.key});

  @override
  State<JourneyModeScreen> createState() => _JourneyModeScreenState();
}

class _JourneyModeScreenState extends State<JourneyModeScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _danger = Color(0xFFEF4444);

  static const List<int> _durationPresets = <int>[10, 30, 60, 180, 480];

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();

  JourneySessionData? _activeJourney;
  bool _loading = true;
  bool _busy = false;
  int _durationIndex = 2;
  String _checkinFrequency = '30';
  double? _latitude;
  double? _longitude;

  Timer? _locationPingTimer;
  Timer? _overdueTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _locationPingTimer?.cancel();
    _overdueTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadCurrentLocation();
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _activeJourney = await JourneyService.instance.fetchActive(uid);
      if (_activeJourney != null) {
        await _checkOverdue(uid);
        _startLocationPingTimer(uid);
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadCurrentLocation() async {
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
      if (_fromController.text.trim().isEmpty) {
        _fromController.text = 'Current location';
      }
    } catch (_) {
      if (_fromController.text.trim().isEmpty) {
        _fromController.text = 'Current location';
      }
    }
  }

  int get _durationMinutes => _durationPresets[_durationIndex];

  DateTime get _alertAt => DateTime.now().add(Duration(minutes: _durationMinutes));

  String _formatAlertTime(DateTime time) {
    final int hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    if (minutes == 60) {
      return '1 hr';
    }
    if (minutes % 60 == 0) {
      return '${minutes ~/ 60} hr';
    }
    return '$minutes min';
  }

  Future<void> _startJourney() async {
    if (_busy) return;
    final String from = _fromController.text.trim();
    final String to = _toController.text.trim();
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both start and destination.')),
      );
      return;
    }

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required to use Journey mode.')),
      );
      return;
    }

    setState(() => _busy = true);
    HapticFeedback.mediumImpact();

    final JourneySessionData? session = await JourneyService.instance.startJourney(
      uid: uid,
      fromLocation: from,
      toLocation: to,
      durationMinutes: _durationMinutes,
      checkinFrequency: _checkinFrequency,
      latitude: _latitude,
      longitude: _longitude,
    );

    if (session == null) {
      if (!mounted) return;
      setState(() => _busy = false);
      final String message = JourneyService.instance.lastStartError ??
          'Could not start journey. Check your connection.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    await JourneyScheduler.instance.scheduleForSession(session);

    if (!mounted) return;
    setState(() {
      _activeJourney = session;
      _busy = false;
    });
    _startLocationPingTimer(uid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journey started — contacts will be alerted if you do not arrive.')),
    );
  }

  Future<void> _confirmArrival() async {
    if (_busy || _activeJourney == null) return;
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    setState(() => _busy = true);
    _stopLocationPingTimer();
    await JourneyScheduler.instance.cancelAll();
    await JourneyService.instance.confirmArrival(
      uid: uid,
      journeyId: _activeJourney!.journeyId,
      latitude: _latitude,
      longitude: _longitude,
    );
    if (!mounted) return;
    setState(() {
      _activeJourney = null;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arrival confirmed — journey ended safely.')),
    );
  }

  Future<void> _cancelJourney() async {
    if (_busy || _activeJourney == null) return;
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    setState(() => _busy = true);
    _stopLocationPingTimer();
    await JourneyScheduler.instance.cancelAll();
    await JourneyService.instance.endJourney(
      uid: uid,
      journeyId: _activeJourney!.journeyId,
    );
    if (!mounted) return;
    setState(() {
      _activeJourney = null;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journey cancelled.')),
    );
  }

  void _startLocationPingTimer(String uid) {
    _locationPingTimer?.cancel();
    _overdueTimer?.cancel();

    _locationPingTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_pingCurrentLocation(uid));
    });

    _overdueTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_checkOverdue(uid));
    });
  }

  void _stopLocationPingTimer() {
    _locationPingTimer?.cancel();
    _overdueTimer?.cancel();
    _locationPingTimer = null;
    _overdueTimer = null;
  }

  Future<void> _pingCurrentLocation(String uid) async {
    final JourneySessionData? journey = _activeJourney;
    if (journey == null || !journey.isActive) {
      return;
    }
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      _latitude = position.latitude;
      _longitude = position.longitude;
      await JourneyService.instance.pingLocation(
        uid: uid,
        journeyId: journey.journeyId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await SafetyService.instance.updateLocation(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
        address: journey.toLocation,
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _checkOverdue(String uid) async {
    final JourneySessionData? journey = _activeJourney;
    if (journey == null || !journey.isActive) {
      return;
    }
    if (!DateTime.now().isAfter(journey.expectedArrivalAt)) {
      return;
    }
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    _stopLocationPingTimer();
    await JourneyScheduler.instance.cancelAll();
    final bool missed = await JourneyService.instance.markMissedIfOverdue(
      uid: uid,
      session: journey,
    );
    if (!mounted) return;
    setState(() {
      _activeJourney = null;
      _busy = false;
    });
    if (missed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Expected arrival time passed — your contacts have been alerted.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: _background,
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    return ColoredBox(
      color: _background,
      child: SafeArea(
        child: _activeJourney != null ? _buildActiveBody() : _buildSetupBody(),
      ),
    );
  }

  Widget _buildSetupBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: 14),
        Text(
          'Set your destination and expected arrival time. If you don\'t confirm arrival, SafeCheck alerts your contacts.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 22),
        _buildRouteCard(),
        const SizedBox(height: 14),
        _buildDurationCard(),
        const SizedBox(height: 14),
        _buildFrequencyCard(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _startJourney,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _busy ? 'Starting…' : 'Start Journey →',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveBody() {
    final JourneySessionData journey = _activeJourney!;
    final Duration remaining = journey.expectedArrivalAt.difference(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        _buildHeader(active: true),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Journey in progress',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildRouteSummary(journey),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ALERT FIRES AT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: _accent.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatAlertTime(journey.expectedArrivalAt),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining.isNegative
                    ? 'Overdue — confirm arrival or contacts may be alerted'
                    : '${remaining.inMinutes} min remaining',
                style: TextStyle(
                  fontSize: 13,
                  color: remaining.isNegative
                      ? _danger
                      : Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _confirmArrival,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2F5D4E),
              foregroundColor: const Color(0xFFBBF7D0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _busy ? 'Saving…' : 'I\'ve arrived safely',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _busy ? null : _cancelJourney,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Cancel journey'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({bool active = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            'Journey Mode',
            style: const TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color: Colors.white,
            ),
          ),
        ),
        if (!active)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.45)),
            ),
            child: const Text(
              'NEW V2',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Color(0xFF93C5FD),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRouteCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 52,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _danger,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: <Widget>[
                _routeField(
                  label: 'FROM',
                  controller: _fromController,
                  hint: 'Start location',
                ),
                const SizedBox(height: 12),
                _routeField(
                  label: 'TO',
                  controller: _toController,
                  hint: 'Destination',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
            filled: true,
            fillColor: const Color(0xFF0A192F),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteSummary(JourneySessionData journey) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _summaryRow('FROM', journey.fromLocation, _accent),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          ),
          _summaryRow('TO', journey.toLocation, _danger),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color dotColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'EXPECTED ARRIVAL TIME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: _accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How long should this journey take?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '$_durationMinutes',
                style: const TextStyle(
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'minutes · Alert fires at ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _formatAlertTime(_alertAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: Colors.white,
              overlayColor: _accent.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: _durationIndex.toDouble(),
              min: 0,
              max: (_durationPresets.length - 1).toDouble(),
              divisions: _durationPresets.length - 1,
              onChanged: (double value) {
                setState(() => _durationIndex = value.round());
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _durationPresets
                .map(
                  (int minutes) => Text(
                    _durationLabel(minutes),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'CHECK-IN FREQUENCY DURING JOURNEY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: _accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          _frequencyChip('No mid-journey check-in', 'none', fullWidth: true),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: _frequencyChip('Every 30 min', '30')),
              const SizedBox(width: 10),
              Expanded(child: _frequencyChip('Every 1 hour', '60')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frequencyChip(
    String label,
    String value, {
    bool fullWidth = false,
  }) {
    final bool selected = _checkinFrequency == value;
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _checkinFrequency = value),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? _accent.withValues(alpha: 0.1)
                  : const Color(0xFF0A192F),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? _accent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? _accent : Colors.white.withValues(alpha: 0.62),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
