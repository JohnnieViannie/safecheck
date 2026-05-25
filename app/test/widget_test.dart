// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:safecheck/models/user_model.dart';

void main() {
  test('user model parses new safety fields', () {
    final user = UserModel.fromMap(<String, dynamic>{
      'uid': 'u1',
      'onboarding_completed': true,
      'checkin_time': '18:00',
      'timezone': 'WAT',
      'emergency_contact_relationship': 'Sister',
      'emergency_contact_email': 'kin@example.com',
      'last_call_status': 'in_progress',
      'escalation_status': 'none',
    });

    expect(user.uid, 'u1');
    expect(user.onboardingCompleted, true);
    expect(user.checkinTime, '18:00');
    expect(user.emergencyContactRelationship, 'Sister');
    expect(user.emergencyContactEmail, 'kin@example.com');
    expect(user.lastCallStatus, 'in_progress');
    expect(user.escalationStatus, 'none');
  });
}
