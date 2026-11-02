import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/utils/checkin_history.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.onGoCheckIn});

  final VoidCallback? onGoCheckIn;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _safe = Color(0xFF4ADE80);
  static const Color _late = Color(0xFFFBBF24);
  static const Color _missed = Color(0xFFF87171);

  List<Map<String, dynamic>> _checkins = <Map<String, dynamic>>[];
  String _checkinTime = '18:00';
  Duration _gracePeriod = const Duration(hours: 2);
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    final Duration grace = await StorageService.instance.getGracePeriod();
    List<Map<String, dynamic>> checkins = <Map<String, dynamic>>[];
    String checkinTime = '18:00';

    if (uid != null && uid.isNotEmpty) {
      final profile = await AuthService.instance.getUserProfile(uid);
      if ((profile?.checkinTime ?? '').trim().isNotEmpty) {
        checkinTime = profile!.checkinTime!.trim();
      }
      checkins = await SafetyService.instance.fetchCheckins(uid);
    }

    if (!mounted) return;
    setState(() {
      _checkins = checkins;
      _checkinTime = checkinTime;
      _gracePeriod = grace;
      _loading = false;
    });
  }

  CheckinHistory get _history => CheckinHistory(
        checkinTime: _checkinTime,
        gracePeriod: _gracePeriod,
      );

  Color _statusColor(CheckinDayStatus status) {
    switch (status) {
      case CheckinDayStatus.onTime:
        return _safe;
      case CheckinDayStatus.late:
        return _late;
      case CheckinDayStatus.missed:
        return _missed;
      case CheckinDayStatus.pending:
      case CheckinDayStatus.none:
        return Colors.white.withValues(alpha: 0.18);
    }
  }

  String _badgeLabel(CheckinDayStatus status) {
    switch (status) {
      case CheckinDayStatus.onTime:
        return 'SAFE';
      case CheckinDayStatus.late:
        return 'LATE';
      case CheckinDayStatus.missed:
        return 'MISSED';
      case CheckinDayStatus.pending:
        return 'PENDING';
      case CheckinDayStatus.none:
        return '—';
    }
  }

  Future<void> _exportHistory() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required to export history.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final response = await ApiService.instance.get(
        Endpoints.exportCheckins,
        query: <String, dynamic>{'uid': uid},
      );
      if (response.statusCode != 200) {
        throw StateError('Export failed (${response.statusCode})');
      }
      final Directory tempDir = await getTemporaryDirectory();
      final File file = File('${tempDir.path}/safecheck-history-$uid.csv');
      await file.writeAsBytes(response.bodyBytes);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: 'SafeCheck history',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not export history. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<CheckinDayStatus> week =
        _history.buildWeekStatuses(_checkins, DateTime.now());
    final List<CheckinLogEntry> logs =
        _history.buildLogEntries(_checkins, context);

    return ColoredBox(
      color: _background,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              color: _accent,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildHeader(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('THIS WEEK'),
                          const SizedBox(height: 14),
                          _buildWeekChart(week),
                          const SizedBox(height: 28),
                          _buildSectionLabel('FULL LOG'),
                          const SizedBox(height: 14),
                          if (logs.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _cardBackground,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'No check-in history yet.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.58),
                                    ),
                                  ),
                                  if (widget.onGoCheckIn != null) ...<Widget>[
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: widget.onGoCheckIn,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _accent,
                                        foregroundColor: const Color(0xFF0A192F),
                                      ),
                                      child: const Text('Go check in'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          else
                            ...logs.map(_buildLogCard),
                        ],
                      ),
                    ),
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
          'History',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
            color: Colors.white,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _exporting ? null : _exportHistory,
          child: Text(
            _exporting ? 'EXPORTING…' : 'EXPORT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: _accent.withValues(alpha: 0.95),
            ),
          ),
        ),
      ],
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

  Widget _buildWeekChart(List<CheckinDayStatus> week) {
    const List<String> labels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(7, (int index) {
                final CheckinDayStatus status = week[index];
                final Color color = _statusColor(status);
                final double heightFactor = switch (status) {
                  CheckinDayStatus.onTime => 1.0,
                  CheckinDayStatus.late => 0.72,
                  CheckinDayStatus.missed => 1.0,
                  CheckinDayStatus.pending => 0.08,
                  CheckinDayStatus.none => 0.08,
                };

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          height: 88 * heightFactor,
                          decoration: BoxDecoration(
                            color: color.withValues(
                              alpha: status == CheckinDayStatus.none ||
                                      status == CheckinDayStatus.pending
                                  ? 0.35
                                  : 0.95,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _legendDot(_safe, 'On time'),
              const SizedBox(width: 16),
              _legendDot(_late, 'Late'),
              const SizedBox(width: 16),
              _legendDot(_missed, 'Missed'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.52),
          ),
        ),
      ],
    );
  }

  Widget _buildLogCard(CheckinLogEntry entry) {
    final Color color = _statusColor(entry.status);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _history.formatLogHeading(entry.when),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _badgeLabel(entry.status),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.detail,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
