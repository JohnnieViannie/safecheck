class UserModel {
  UserModel({
    required this.uid,
    required this.onboardingCompleted,
    this.fullName,
    this.email,
    this.phoneNumber,
    this.userType,
    this.checkinFrequency,
    this.gracePeriodHours,
    this.gracePeriodMinutes,
    this.emergencyContactName,
    this.emergencyContactRelationship,
    this.emergencyContactCountryCode,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.emergencyContactsJson,
    this.notificationPrefsJson,
    this.pinSet = false,
    this.lastCheckInAt,
    this.checkinTime,
    this.timezone,
    this.lastCallStatus,
    this.escalationStatus,
    this.snoozedUntil,
  });

  final String uid;
  final bool onboardingCompleted;
  final String? fullName;
  final String? email;
  final String? phoneNumber;
  final String? userType;
  final String? checkinFrequency;
  final int? gracePeriodHours;
  final int? gracePeriodMinutes;
  final String? emergencyContactName;
  final String? emergencyContactRelationship;
  final String? emergencyContactCountryCode;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? emergencyContactsJson;
  final String? notificationPrefsJson;
  final bool pinSet;
  final DateTime? lastCheckInAt;
  final String? checkinTime;
  final String? timezone;
  final String? lastCallStatus;
  final String? escalationStatus;
  final DateTime? snoozedUntil;

  /// The best display identifier: prefers phone, falls back to email, then uid.
  String get displayIdentifier {
    if (phoneNumber?.isNotEmpty ?? false) return phoneNumber!;
    if (email?.isNotEmpty ?? false) return email!;
    return uid;
  }

  /// First name for greetings — uses [fullName], not email.
  String get firstName {
    final String? name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    return 'there';
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phoneNumber,
      'onboardingCompleted': onboardingCompleted,
      'userType': userType,
      'checkinFrequency': checkinFrequency,
      'gracePeriodHours': gracePeriodHours,
      'gracePeriodMinutes': gracePeriodMinutes,
      'emergencyContactName': emergencyContactName,
      'emergencyContactRelationship': emergencyContactRelationship,
      'emergencyContactCountryCode': emergencyContactCountryCode,
      'emergencyContactPhone': emergencyContactPhone,
      'emergencyContactEmail': emergencyContactEmail,
      'emergencyContactsJson': emergencyContactsJson,
      'notificationPrefsJson': notificationPrefsJson,
      'pinSet': pinSet,
      'lastCheckInAt': lastCheckInAt?.millisecondsSinceEpoch,
      'checkinTime': checkinTime,
      'timezone': timezone,
      'lastCallStatus': lastCallStatus,
      'escalationStatus': escalationStatus,
      'snoozedUntil': snoozedUntil?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
      fullName: map['fullName'] as String? ?? map['full_name'] as String?,
      email: map['email'] as String?,
      phoneNumber:
          map['phoneNumber'] as String? ?? map['phone_number'] as String?,
      onboardingCompleted:
          map['onboardingCompleted'] as bool? ??
          map['onboarding_completed'] as bool? ??
          false,
      userType: map['userType'] as String? ?? map['user_type'] as String?,
      checkinFrequency:
          map['checkinFrequency'] as String? ??
          map['checkin_frequency'] as String?,
      gracePeriodHours:
          map['gracePeriodHours'] as int? ?? map['grace_period_hours'] as int?,
      gracePeriodMinutes: map['gracePeriodMinutes'] as int? ??
          map['grace_period_minutes'] as int?,
      emergencyContactName:
          map['emergencyContactName'] as String? ??
          map['emergency_contact_name'] as String?,
      emergencyContactRelationship:
          map['emergencyContactRelationship'] as String? ??
          map['emergency_contact_relationship'] as String?,
      emergencyContactCountryCode:
          map['emergencyContactCountryCode'] as String? ??
          map['emergency_contact_country_code'] as String?,
      emergencyContactPhone:
          map['emergencyContactPhone'] as String? ??
          map['emergency_contact_phone'] as String?,
      emergencyContactEmail:
          map['emergencyContactEmail'] as String? ??
          map['emergency_contact_email'] as String?,
      emergencyContactsJson:
          map['emergencyContactsJson'] as String? ??
          map['emergency_contacts_json'] as String?,
      notificationPrefsJson:
          map['notificationPrefsJson'] as String? ??
          map['notification_prefs_json'] as String?,
      pinSet: map['pinSet'] as bool? ??
          map['pin_set'] as bool? ??
          ((map['pin'] as String?)?.trim().isNotEmpty ?? false),
      lastCheckInAt:
          map['lastCheckInAt'] == null && map['last_check_in_at'] == null
          ? null
          : map['lastCheckInAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastCheckInAt'] as int)
          : DateTime.tryParse(map['last_check_in_at'] as String? ?? ''),
      checkinTime:
          map['checkinTime'] as String? ?? map['checkin_time'] as String?,
      timezone: map['timezone'] as String?,
      lastCallStatus:
          map['lastCallStatus'] as String? ??
          map['last_call_status'] as String?,
      escalationStatus:
          map['escalationStatus'] as String? ??
          map['escalation_status'] as String?,
      snoozedUntil: _parseDateTime(map['snoozedUntil'] ?? map['snoozed_until']),
    );
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return DateTime.tryParse(raw.toString());
  }
}
