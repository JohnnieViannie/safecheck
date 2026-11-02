import 'package:flutter/material.dart';
import 'package:safecheck/screens/checkin_screen.dart';
import 'package:safecheck/screens/grace_period_screen.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';

Future<SimulatedCallResult?> pushCheckinFlow(
  BuildContext context, {
  required SimulatedCallContext contextData,
  required Duration gracePeriod,
}) {
  final DateTime now = DateTime.now();
  final bool inGrace = now.isAfter(contextData.scheduledFor);

  if (inGrace) {
    return Navigator.of(context).push<SimulatedCallResult>(
      MaterialPageRoute<SimulatedCallResult>(
        builder: (_) => GracePeriodScreen(
          scheduledFor: contextData.scheduledFor,
          gracePeriod: gracePeriod,
        ),
      ),
    );
  }

  return Navigator.of(context).push<SimulatedCallResult>(
    MaterialPageRoute<SimulatedCallResult>(
      builder: (_) => CheckinScreen(
        contextData: contextData,
        gracePeriod: gracePeriod,
      ),
    ),
  );
}
