class JourneySessionData {
  const JourneySessionData({
    required this.journeyId,
    required this.fromLocation,
    required this.toLocation,
    required this.durationMinutes,
    required this.checkinFrequency,
    required this.startedAt,
    required this.expectedArrivalAt,
    this.arrivedAt,
    this.status = 'active',
    this.lastLatitude,
    this.lastLongitude,
  });

  factory JourneySessionData.fromJson(Map<String, dynamic> json) {
    return JourneySessionData(
      journeyId: json['journey_id']?.toString() ?? '',
      fromLocation: json['from_location']?.toString() ?? '',
      toLocation: json['to_location']?.toString() ?? '',
      durationMinutes: json['duration_minutes'] as int? ?? 60,
      checkinFrequency: json['checkin_frequency']?.toString() ?? 'none',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.now(),
      expectedArrivalAt:
          DateTime.tryParse(json['expected_arrival_at']?.toString() ?? '') ??
              DateTime.now(),
      arrivedAt: DateTime.tryParse(json['arrived_at']?.toString() ?? ''),
      status: json['status']?.toString() ?? 'active',
      lastLatitude: (json['last_latitude'] as num?)?.toDouble(),
      lastLongitude: (json['last_longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'journey_id': journeyId,
      'from_location': fromLocation,
      'to_location': toLocation,
      'duration_minutes': durationMinutes,
      'checkin_frequency': checkinFrequency,
      'started_at': startedAt.toIso8601String(),
      'expected_arrival_at': expectedArrivalAt.toIso8601String(),
      'arrived_at': arrivedAt?.toIso8601String(),
      'status': status,
      'last_latitude': lastLatitude,
      'last_longitude': lastLongitude,
    };
  }

  final String journeyId;
  final String fromLocation;
  final String toLocation;
  final int durationMinutes;
  final String checkinFrequency;
  final DateTime startedAt;
  final DateTime expectedArrivalAt;
  final DateTime? arrivedAt;
  final String status;
  final double? lastLatitude;
  final double? lastLongitude;

  bool get isActive => status == 'active';
}
