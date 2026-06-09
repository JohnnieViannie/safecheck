import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/alarm_watchdog.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/reliable_alarm_permissions.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';

/// Mandatory checklist so check-in alarms can fire while the phone sleeps.
class AlarmSetupScreen extends StatefulWidget {
  const AlarmSetupScreen({super.key});

  @override
  State<AlarmSetupScreen> createState() => _AlarmSetupScreenState();
}

class _AlarmSetupScreenState extends State<AlarmSetupScreen> {
  AlarmSetupStatus _status = const AlarmSetupStatus(
    exactAlarmGranted: false,
    batteryOptimizationDisabled: false,
    notificationsGranted: false,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final AlarmSetupStatus status =
        await ReliableAlarmPermissions.checkAndroidAlarmSetup();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  int get _completedCount {
    int count = 0;
    if (_status.exactAlarmGranted) count++;
    if (_status.notificationsGranted) count++;
    if (_status.batteryOptimizationDisabled) count++;
    return count;
  }

  Future<void> _continue() async {
    if (!_status.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Allow "Alarms & reminders" before continuing — check-in calls need it.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.secondary,
        ),
      );
      return;
    }

    await AlarmScheduler.instance.ensureAlarmsScheduled();
    await PushCheckinService.instance.registerTokenIfLoggedIn();
    AlarmWatchdog.instance.attach();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0A0F14),
      ),
      child: Theme(
        data: AppTheme.darkTheme,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0F14),
          body: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      _buildCompactHeader(),
                      const SizedBox(height: 16),
                      _buildProgressHeader(),
                      const SizedBox(height: 8),
                      Text(
                        'Allow these so check-in calls ring when your phone is locked.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                            ),
                          ),
                        )
                      else ...<Widget>[
                        _ChecklistTile(
                          icon: Icons.alarm_rounded,
                          iconColor: AppTheme.primary,
                          title: 'Alarms & reminders',
                          subtitle: 'Allows exact check-in times',
                          done: _status.exactAlarmGranted,
                          required: true,
                          onTap: () async {
                            await ReliableAlarmPermissions.requestExactAlarm();
                            await _refresh();
                          },
                        ),
                        const SizedBox(height: 10),
                        _ChecklistTile(
                          icon: Icons.notifications_active_rounded,
                          iconColor: const Color(0xFF5C9CE6),
                          title: 'Notifications',
                          subtitle: 'Shows incoming check-in calls',
                          done: _status.notificationsGranted,
                          onTap: () async {
                            await ReliableAlarmPermissions
                                .requestNotifications();
                            await _refresh();
                          },
                        ),
                        const SizedBox(height: 10),
                        _ChecklistTile(
                          icon: Icons.battery_charging_full_rounded,
                          iconColor: const Color(0xFFE6A85C),
                          title: 'Battery optimization off',
                          subtitle: 'Stops the phone from killing alarms',
                          done: _status.batteryOptimizationDisabled,
                          onTap: () async {
                            await ReliableAlarmPermissions
                                .requestBatteryExemption();
                            await _refresh();
                          },
                        ),
                        if (Platform.isAndroid) ...<Widget>[
                          const SizedBox(height: 10),
                          _ChecklistTile(
                            icon: Icons.phonelink_setup_rounded,
                            iconColor: const Color(0xFF9B7EDE),
                            title: 'Autostart / background',
                            subtitle:
                                'Enable in manufacturer settings on some phones',
                            done: false,
                            optional: true,
                            onTap: ReliableAlarmPermissions
                                .openOemAutostartSettings,
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (!_status.isReady)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Complete the required items above to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        _buildContinueButton(),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Row(
      children: <Widget>[
        const AppLogo(height: 28),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Permissions',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressHeader() {
    const int total = 3;
    final int done = _completedCount;
    final double fraction = total > 0 ? done / total : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Setup progress',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            Text(
              '$done of $total done',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _status.isReady
                    ? const Color(0xFF4ADE80)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _loading ? null : fraction,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: _status.isReady
                ? const Color(0xFF4ADE80)
                : AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    final bool ready = _status.isReady && !_loading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading ? null : _continue,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: ready
                ? const LinearGradient(
                    colors: <Color>[Color(0xFF1F6F8B), Color(0xFF2A8FAF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: ready ? null : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: ready
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            ready ? 'Continue to home' : 'Grant required permissions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ready ? Colors.white : Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
    this.required = false,
    this.optional = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool done;
  final bool required;
  final bool optional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color statusColor =
        done ? const Color(0xFF4ADE80) : AppTheme.primary;
    final Color statusBg =
        done
            ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
            : AppTheme.primary.withValues(alpha: 0.12);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 340;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141A22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: done
                      ? const Color(0xFF4ADE80).withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: narrow
                  ? _buildStackedLayout(statusColor, statusBg)
                  : _buildRowLayout(statusColor, statusBg),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgeRow() {
    if (!required && !optional) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          if (required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Required',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondary,
                ),
              ),
            ),
          if (optional)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Optional',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }

  Widget _buildTextColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        _buildBadgeRow(),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _statusPill(Color statusColor, Color statusBg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        done ? 'Done' : 'Fix',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: statusColor,
        ),
      ),
    );
  }

  Widget _buildRowLayout(Color statusColor, Color statusBg) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildIcon(),
        const SizedBox(width: 12),
        Expanded(child: _buildTextColumn()),
        const SizedBox(width: 8),
        _statusPill(statusColor, statusBg),
      ],
    );
  }

  Widget _buildStackedLayout(Color statusColor, Color statusBg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildIcon(),
            const SizedBox(width: 12),
            Expanded(child: _buildTextColumn()),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: _statusPill(statusColor, statusBg),
        ),
      ],
    );
  }
}
