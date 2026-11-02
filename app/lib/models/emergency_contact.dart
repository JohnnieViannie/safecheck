import 'dart:convert';

class EmergencyContact {
  EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.countryCode,
    required this.dialCode,
    required this.phone,
    this.email = '',
    this.role = 'secondary',
    this.optInStatus = 'pending',
  });

  final String id;
  final String name;
  final String relationship;
  final String countryCode;
  final String dialCode;
  final String phone;
  final String email;
  final String role;
  final String optInStatus;

  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get roleLabel {
    switch (role.toLowerCase()) {
      case 'primary':
        return 'PRIMARY';
      case 'secondary':
        return 'SECONDARY';
      default:
        return role.toUpperCase();
    }
  }

  String get optInLabel {
    switch (optInStatus.toLowerCase()) {
      case 'opt_in':
      case 'opt-in':
      case 'opted_in':
        return 'OPT-IN ✓';
      case 'pending':
        return 'PENDING';
      default:
        return optInStatus.toUpperCase();
    }
  }

  bool get isOptedIn =>
      optInStatus.toLowerCase() == 'opt_in' ||
      optInStatus.toLowerCase() == 'opt-in' ||
      optInStatus.toLowerCase() == 'opted_in';

  String get subtitleLine {
    final String relation = relationship.trim().isEmpty
        ? 'Contact'
        : _capitalize(relationship.trim());
    final String phoneLine = formattedPhone.trim();
    if (phoneLine.isEmpty) {
      return relation;
    }
    return '$relation · $phoneLine';
  }

  String get formattedPhone {
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (dialCode.trim().isNotEmpty && digits.isNotEmpty) {
      final String grouped = _groupDigits(digits);
      return '${dialCode.trim()} $grouped'.trim();
    }
    return phone.trim();
  }

  Map<String, dynamic> toMap({String? roleOverride, String? optInOverride}) {
    return <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'relationship': relationship.trim(),
      'country_code': countryCode,
      'dial_code': dialCode,
      'phone': phone.trim(),
      'email': email.trim(),
      'role': roleOverride ?? role,
      'opt_in_status': optInOverride ?? optInStatus,
    };
  }

  EmergencyContact copyWith({
    String? name,
    String? relationship,
    String? countryCode,
    String? dialCode,
    String? phone,
    String? role,
    String? optInStatus,
  }) {
    return EmergencyContact(
      id: id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      countryCode: countryCode ?? this.countryCode,
      dialCode: dialCode ?? this.dialCode,
      phone: phone ?? this.phone,
      email: email,
      role: role ?? this.role,
      optInStatus: optInStatus ?? this.optInStatus,
    );
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  static String _groupDigits(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    if (digits.length <= 6) {
      return '${digits.substring(0, 3)} ${digits.substring(3)}';
    }
    if (digits.length <= 9) {
      return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    }
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 9)} ${digits.substring(9)}';
  }

  factory EmergencyContact.fromMap(
    Map<String, dynamic> map, {
    required int index,
  }) {
    final String role =
        (map['role'] as String? ?? (index == 0 ? 'primary' : 'secondary'))
            .toLowerCase();
    final String optIn = map['opt_in_status'] as String? ??
        map['optInStatus'] as String? ??
        (role == 'primary' ? 'opt_in' : 'pending');

    return EmergencyContact(
      id: map['id'] as String? ?? '$index',
      name: map['name'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      countryCode: map['country_code'] as String? ?? 'UG',
      dialCode: map['dial_code'] as String? ?? '+256',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: role,
      optInStatus: optIn,
    );
  }

  static List<EmergencyContact> listFromProfile(Map<String, dynamic> profile) {
    final dynamic raw = profile['emergency_contacts_json'] ??
        profile['emergencyContactsJson'];

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .toList()
              .asMap()
              .entries
              .map(
                (MapEntry<int, Map<String, dynamic>> entry) =>
                    EmergencyContact.fromMap(entry.value, index: entry.key),
              )
              .where((EmergencyContact contact) => contact.name.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Fall through to legacy single-contact fields.
      }
    }

    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .toList()
          .asMap()
          .entries
          .map(
            (MapEntry<int, Map<String, dynamic>> entry) =>
                EmergencyContact.fromMap(entry.value, index: entry.key),
          )
          .where((EmergencyContact contact) => contact.name.trim().isNotEmpty)
          .toList();
    }

    final String? name = profile['emergency_contact_name'] as String? ??
        profile['emergencyContactName'] as String?;
    if (name == null || name.trim().isEmpty) {
      return <EmergencyContact>[];
    }

    return <EmergencyContact>[
      EmergencyContact(
        id: 'primary',
        name: name.trim(),
        relationship:
            (profile['emergency_contact_relationship'] as String? ??
                    profile['emergencyContactRelationship'] as String? ??
                    '')
                .trim(),
        countryCode:
            profile['emergency_contact_country_code'] as String? ?? 'UG',
        dialCode: '+256',
        phone: (profile['emergency_contact_phone'] as String? ?? '').trim(),
        email:
            (profile['emergency_contact_email'] as String? ?? '').trim(),
        role: 'primary',
        optInStatus: 'opt_in',
      ),
    ];
  }
}
