class UserModel {
  UserModel({
    required this.uid,
    required this.onboardingCompleted,
    this.email,
    this.phoneNumber,
    this.userType,
    this.checkinFrequency,
    this.gracePeriodHours,
    this.emergencyContactName,
    this.emergencyContactRelationship,
    this.emergencyContactCountryCode,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.pin,
    this.lastCheckInAt,
    this.checkinTime,
    this.timezone,
    this.lastCallStatus,
    this.escalationStatus,
  });

  final String uid;
  final bool onboardingCompleted;
  final String? email;
  final String? phoneNumber;
  final String? userType;
  final String? checkinFrequency;
  final int? gracePeriodHours;
  final String? emergencyContactName;
  final String? emergencyContactRelationship;
  final String? emergencyContactCountryCode;
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final String? pin;
  final DateTime? lastCheckInAt;
  final String? checkinTime;
  final String? timezone;
  final String? lastCallStatus;
  final String? escalationStatus;

  /// The best display identifier: prefers email, falls back to phone, then uid.
  String get displayIdentifier => email ?? phoneNumber ?? uid;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'email': email,
      'phoneNumber': phoneNumber,
      'onboardingCompleted': onboardingCompleted,
      'userType': userType,
      'checkinFrequency': checkinFrequency,
      'gracePeriodHours': gracePeriodHours,
      'emergencyContactName': emergencyContactName,
      'emergencyContactRelationship': emergencyContactRelationship,
      'emergencyContactCountryCode': emergencyContactCountryCode,
      'emergencyContactPhone': emergencyContactPhone,
      'emergencyContactEmail': emergencyContactEmail,
      'pin': pin,
      'lastCheckInAt': lastCheckInAt?.millisecondsSinceEpoch,
      'checkinTime': checkinTime,
      'timezone': timezone,
      'lastCallStatus': lastCallStatus,
      'escalationStatus': escalationStatus,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
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
      pin: map['pin'] as String?,
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
    );
  }
}
