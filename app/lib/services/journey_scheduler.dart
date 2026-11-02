import 'package:safecheck/models/journey_session.dart';
import 'package:safecheck/services/notification_service.dart';

class JourneyScheduler {
  JourneyScheduler._();

  static final JourneyScheduler instance = JourneyScheduler._();

  Future<void> scheduleForSession(JourneySessionData session) async {
    await NotificationService.instance.scheduleJourneyNotifications(
      journeyId: session.journeyId,
      startedAt: session.startedAt,
      expectedArrivalAt: session.expectedArrivalAt,
      checkinFrequency: session.checkinFrequency,
    );
  }

  Future<void> cancelAll() async {
    await NotificationService.instance.cancelJourneyNotifications();
  }
}
