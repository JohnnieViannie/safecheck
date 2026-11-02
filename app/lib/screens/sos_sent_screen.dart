import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/models/emergency_contact.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/biometric_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SosSentScreen extends StatefulWidget {
  const SosSentScreen({
    super.key,
    required this.firedAt,
    this.latitude,
    this.longitude,
    this.discreet = false,
  });

  final DateTime firedAt;
  final double? latitude;
  final double? longitude;
  final bool discreet;

  @override
  State<SosSentScreen> createState() => _SosSentScreenState();
}

class _SosSentScreenState extends State<SosSentScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _safeButton = Color(0xFF2F5D4E);
  static const Color _accent = Color(0xFF14B8A6);

  String _contactsAlerted = 'Your emergency contacts';
  String _primaryContactName = 'your contacts';
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    BiometricLockSession.suppressPrompts();
    unawaited(_loadContacts());
  }

  @override
  void dispose() {
    BiometricLockSession.releasePrompts();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      final response = await ApiService.instance.get(
        '${Endpoints.userProfile}$uid/',
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        final List<EmergencyContact> contacts =
            EmergencyContact.listFromProfile(data);
        if (contacts.length >= 2) {
          _contactsAlerted =
              '${_shortName(contacts[0].name)} + ${_shortName(contacts[1].name)}';
        } else if (contacts.isNotEmpty) {
          _contactsAlerted = _shortName(contacts.first.name);
        }
        if (contacts.isNotEmpty) {
          _primaryContactName = contacts.first.name.trim();
        }
      }
    } catch (_) {
      // Keep defaults.
    }

    if (!mounted) return;
    setState(() {});
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

  String _formatTime(DateTime time) {
    final int hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  Future<void> _openMap() async {
    if (widget.latitude == null || widget.longitude == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last location is not available yet.')),
      );
      return;
    }
    final Uri uri = Uri.parse(
      'https://maps.google.com/?q=${widget.latitude},${widget.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _cancelSos() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    HapticFeedback.heavyImpact();

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await StorageService.instance.saveLastCheckIn(DateTime.now());
      await SafetyService.instance.confirmSafe(uid: uid);
      await SafetyService.instance.createCheckin(
        uid: uid,
        status: 'safe_confirmed',
      );
      await SafetyService.instance.logTimelineEvent(
        uid: uid,
        eventType: 'sos_cancelled',
        status: 'safe_confirmed',
      );
    }

    if (!mounted) return;
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
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
        backgroundColor: _background,
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
              stops: <double>[0.0, 0.42, 1.0],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: <Widget>[
                  _buildLiveBanner(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: <Widget>[
                          _buildStatusIcon(),
                          const SizedBox(height: 18),
                          const Text(
                            'SOS Sent',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Georgia',
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Alert sent to $_primaryContactName. Help is on the way.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildSentItemsGrid(),
                          const SizedBox(height: 14),
                          _buildDetailsCard(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE SOS ACTIVE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: _danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _danger.withValues(alpha: 0.1),
        border: Border.all(color: _danger.withValues(alpha: 0.28), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _danger.withValues(alpha: 0.2),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.sos_rounded,
        color: _danger,
        size: 42,
      ),
    );
  }

  Widget _buildSentItemsGrid() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _sentItemChip(
            icon: Icons.location_on_outlined,
            label: 'GPS sent',
            active: widget.latitude != null && widget.longitude != null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sentItemChip(
            icon: Icons.sms_outlined,
            label: 'SMS sent',
            active: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sentItemChip(
            icon: Icons.mic_none_rounded,
            label: 'Recording',
            active: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sentItemChip(
            icon: Icons.folder_open_outlined,
            label: 'Vault',
            active: true,
          ),
        ),
      ],
    );
  }

  Widget _sentItemChip({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final Color color =
        active ? const Color(0xFF4ADE80) : Colors.white.withValues(alpha: 0.35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: _cardBackground.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFF4ADE80).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: active ? 0.88 : 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _cardBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          _detailRow('TIME FIRED', _formatTime(widget.firedAt)),
          _divider(),
          _detailRowLink(
            'LAST LOCATION',
            widget.latitude != null && widget.longitude != null
                ? 'View on map →'
                : 'Unavailable',
            onTap: widget.latitude != null && widget.longitude != null
                ? _openMap
                : null,
          ),
          _divider(),
          _detailRow('CONTACTS ALERTED', _contactsAlerted),
          _divider(),
          _detailRow(
            'RECORDING',
            '• ACTIVE',
            valueColor: const Color(0xFF4ADE80),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _cancelling ? null : _cancelSos,
            style: FilledButton.styleFrom(
              backgroundColor: _safeButton,
              foregroundColor: const Color(0xFFBBF7D0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _cancelling ? 'Cancelling…' : 'I\'m safe — cancel SOS',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _callEmergencyServices,
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Call 999 / Police',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRowLink(
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: onTap == null
                  ? Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    )
                  : GestureDetector(
                      onTap: onTap,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
