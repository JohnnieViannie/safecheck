import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/screens/alarm_setup_screen.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/input_field.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _FrequencyOption {
  const _FrequencyOption({
    required this.id,
    required this.title,
    required this.description,
    this.recommended = false,
  });

  final String id;
  final String title;
  final String description;
  final bool recommended;
}

class _GracePreset {
  const _GracePreset({
    required this.label,
    required this.emoji,
    this.minutes,
    this.isCustom = false,
  });

  final String label;
  final String emoji;
  final int? minutes;
  final bool isCustom;

  String get durationLabel {
    if (isCustom) {
      return 'Set your own';
    }
    final int value = minutes ?? 0;
    if (value < 60) {
      return '$value min';
    }
    if (value % 60 == 0) {
      final int hours = value ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${value ~/ 60}h ${value % 60}m';
  }
}

class _EmergencyContact {
  _EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.countryCode,
    required this.dialCode,
    required this.phone,
    this.email = '',
  });

  final String id;
  String name;
  String relationship;
  String countryCode;
  String dialCode;
  String phone;
  String email;

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

  String get displayPhone {
    final String? e164 = PhoneNumberService.normalizeLocalToE164(
      rawInput: phone,
      isoCode: countryCode,
    );
    if (e164 != null && e164.length >= 8) {
      return '${e164.substring(0, 4)} ${e164.substring(4, 5)}XX XXX XXX';
    }
    final String trimmed = phone.trim();
    if (trimmed.isEmpty) {
      return 'No phone yet';
    }
    return '$dialCode $trimmed';
  }

  Map<String, dynamic> toMap({required String role}) {
    return <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'relationship': relationship.trim(),
      'country_code': countryCode,
      'dial_code': dialCode,
      'phone': phone.trim(),
      'email': email.trim(),
      'role': role,
    };
  }

  factory _EmergencyContact.fromMap(Map<String, dynamic> map) {
    return _EmergencyContact(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      countryCode: map['country_code'] as String? ?? 'UG',
      dialCode: map['dial_code'] as String? ?? '+256',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
    );
  }
}

class _TriggerAction {
  _TriggerAction({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.emoji,
    this.delayMinutes = 0,
    this.enabled = true,
  });

  final String id;
  final String type;
  String title;
  String description;
  final String emoji;
  int delayMinutes;
  bool enabled;

  String delayLabel({required bool isFirst}) {
    if (isFirst && delayMinutes == 0) {
      return 'Immediate';
    }
    if (delayMinutes == 0) {
      return '+0 min';
    }
    if (delayMinutes < 60) {
      return '+$delayMinutes min';
    }
    if (delayMinutes % 60 == 0) {
      final int hours = delayMinutes ~/ 60;
      return hours == 1 ? '+1 hr' : '+$hours hrs';
    }
    return '+$delayMinutes min';
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'emoji': emoji,
      'delay_minutes': delayMinutes,
      'enabled': enabled,
    };
  }

  factory _TriggerAction.fromMap(Map<String, dynamic> map) {
    return _TriggerAction(
      id: map['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: map['type'] as String? ?? 'custom',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      emoji: map['emoji'] as String? ?? '⚡',
      delayMinutes: map['delay_minutes'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }
}

class _PersonaOption {
  const _PersonaOption({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    this.recommendedGraceHours,
    this.footerLabel,
  });

  final String id;
  final String title;
  final String description;
  final String emoji;
  final int? recommendedGraceHours;
  final String? footerLabel;

  String get footerText =>
      footerLabel ??
      'Recommended: ${recommendedGraceHours}hr grace';
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _testGold = Color(0xFFC9A86C);
  static const Color _testGoldText = Color(0xFF0A192F);
  static const List<int> _graceStepMinutes = <int>[
    15,
    30,
    45,
    60,
    90,
    120,
    180,
    240,
    360,
    720,
    1440,
  ];

  static const List<int> _actionDelayOptions = <int>[0, 5, 15, 30, 60, 360, 1440];

  static List<_TriggerAction> _defaultTriggerActions() {
    return <_TriggerAction>[
      _TriggerAction(
        id: 'sms',
        type: 'sms',
        title: 'Send SMS to contacts',
        description: 'Text message with your last location',
        emoji: '💬',
      ),
      _TriggerAction(
        id: 'gps',
        type: 'gps',
        title: 'Share GPS location',
        description: 'Last known coordinates via Maps link',
        emoji: '📍',
      ),
      _TriggerAction(
        id: 'email',
        type: 'email',
        title: 'Send email alert',
        description: 'Detailed message to all contacts',
        emoji: '✉️',
        delayMinutes: 5,
      ),
      _TriggerAction(
        id: 'document_vault',
        type: 'document_vault',
        title: 'Release document vault',
        description: 'Send pre-written document to editor',
        emoji: '📄',
        delayMinutes: 1440,
      ),
    ];
  }

  static List<_TriggerAction> _optionalTriggerActions() {
    return <_TriggerAction>[
      _TriggerAction(
        id: 'whatsapp',
        type: 'whatsapp',
        title: 'Send WhatsApp alert',
        description: 'Instant message to emergency contacts',
        emoji: '📱',
        delayMinutes: 5,
      ),
      _TriggerAction(
        id: 'call_retry',
        type: 'call_retry',
        title: 'Retry safety call',
        description: 'Place another automated check-in call',
        emoji: '📞',
        delayMinutes: 15,
      ),
    ];
  }

  static const List<int> _customMinuteOptions = <int>[0, 15, 30, 45];

  static const List<_FrequencyOption> _frequencyOptions = <_FrequencyOption>[
    _FrequencyOption(
      id: 'Daily',
      title: 'Daily',
      description: 'Recommended for most users',
      recommended: true,
    ),
    _FrequencyOption(
      id: 'Weekly',
      title: 'Weekly',
      description: 'Good for lower-risk routines',
    ),
    _FrequencyOption(
      id: 'Monthly',
      title: 'Monthly',
      description: 'Minimal check-in, peace of mind',
    ),
  ];

  static const List<_GracePreset> _gracePresets = <_GracePreset>[
    _GracePreset(label: 'Living Alone', emoji: '🏠', minutes: 120),
    _GracePreset(label: 'Field Worker', emoji: '🏕️', minutes: 180),
    _GracePreset(label: 'Lone Worker', emoji: '🏗️', minutes: 240),
    _GracePreset(label: 'Traveller', emoji: '✈️', minutes: 360),
    _GracePreset(label: 'Custom', emoji: '⚙️', isCustom: true),
  ];

  static const List<_PersonaOption> _personaOptions = <_PersonaOption>[
    _PersonaOption(
      id: 'Field Worker',
      title: 'Field Worker',
      description: 'Remote sites, travel, outdoor work',
      emoji: '🏕️',
      recommendedGraceHours: 3,
    ),
    _PersonaOption(
      id: 'Living Alone',
      title: 'Living Alone',
      description: 'Solo home, elderly, independent',
      emoji: '👴',
      recommendedGraceHours: 2,
    ),
    _PersonaOption(
      id: 'Lone Worker',
      title: 'Lone Worker',
      description: 'Construction, mining, night shifts',
      emoji: '🏗️',
      recommendedGraceHours: 4,
    ),
    _PersonaOption(
      id: 'Traveller',
      title: 'Traveller',
      description: 'Business trips, solo travel',
      emoji: '✈️',
      recommendedGraceHours: 6,
    ),
    _PersonaOption(
      id: 'Journalist',
      title: 'Journalist',
      description: 'Field reporting, sensitive coverage',
      emoji: '📰',
      recommendedGraceHours: 24,
    ),
    _PersonaOption(
      id: 'Other',
      title: 'Other',
      description: 'Set everything manually',
      emoji: '👤',
      footerLabel: 'Custom settings',
    ),
  ];

  static const List<String> _stepTags = <String>[
    'YOUR NAME',
    'WHO ARE YOU?',
    'CHECK-IN FREQUENCY',
    'GRACE PERIOD',
    'EMERGENCY CONTACTS',
    'TRIGGER ACTIONS',
    'CANCEL PIN',
    'CONFIRM PIN',
    'TEST CHECK',
    'YOU\'RE PROTECTED',
  ];

  static int get _totalSteps => _stepTags.length;

  int _step = 0;
  bool _saving = false;
  bool _profileSaved = false;
  String? _error;

  String? _selectedUserType;
  String _frequency = 'Daily';
  int _graceMinutes = 120;
  bool _graceCustomMode = false;
  int _customGraceHours = 2;
  int _customGraceMinutes = 0;
  TimeOfDay _checkinTime = const TimeOfDay(hour: 18, minute: 0);
  List<_EmergencyContact> _emergencyContacts = <_EmergencyContact>[];
  List<_TriggerAction> _triggerActions = _OnboardingScreenState._defaultTriggerActions();

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _pinConfirmController = TextEditingController();
  String _pinDraft = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadDraft());
  }

  @override
  void reassemble() {
    super.reassemble();
    _normalizeStep();
  }

  void _normalizeStep() {
    final int clamped = _step.clamp(0, _totalSteps - 1);
    if (clamped != _step) {
      _step = clamped;
    }
  }

  int get _effectiveStep => _step.clamp(0, _totalSteps - 1);

  Future<void> _loadDraft() async {
    Map<String, dynamic>? localDraft;
    try {
      localDraft = await StorageService.instance.getOnboardingDraft();
    } catch (_) {
      // Can happen after hot reload when StorageService was updated in code.
    }

    Map<String, dynamic>? serverDraft;
    final UserModel? user = await AuthService.instance.resolveSessionUser();
    if (user != null) {
      serverDraft = await AuthService.instance.getOnboardingDraft(user.uid);
    }

    final int localStep = localDraft?['step'] as int? ?? -1;
    final int serverStep = serverDraft?['step'] as int? ?? -1;
    final Map<String, dynamic>? chosenDraft;
    if (serverDraft != null && serverStep >= localStep) {
      chosenDraft = serverDraft;
    } else {
      chosenDraft = localDraft;
    }

    if (chosenDraft == null || !mounted) {
      return;
    }

    _applyDraft(chosenDraft);
  }

  void _applyDraft(Map<String, dynamic> saved) {
    if (!mounted) {
      return;
    }
    setState(() {
      final int savedStep = saved['step'] as int? ?? _step;
      _step = savedStep.clamp(0, _totalSteps - 1);
      _fullNameController.text = saved['full_name'] as String? ?? '';
      _selectedUserType = _migrateUserType(saved['user_type'] as String?);
      _frequency = saved['frequency'] as String? ?? _frequency;
      if (saved['grace_minutes'] != null) {
        _graceMinutes = _snapGraceMinutes(saved['grace_minutes'] as int);
      } else if (saved['grace_hours'] != null) {
        _graceMinutes = _snapGraceMinutes((saved['grace_hours'] as int) * 60);
      }
      _graceCustomMode = saved['grace_custom_mode'] as bool? ?? false;
      _customGraceHours = saved['custom_grace_hours'] as int? ?? _graceMinutes ~/ 60;
      _customGraceMinutes =
          saved['custom_grace_minutes'] as int? ?? _graceMinutes % 60;
      final int? hour = saved['checkin_hour'] as int?;
      final int? minute = saved['checkin_minute'] as int?;
      if (hour != null && minute != null) {
        _checkinTime = TimeOfDay(hour: hour, minute: minute);
      }
      final List<dynamic>? savedContacts =
          saved['kin_contacts'] as List<dynamic>?;
      if (savedContacts != null && savedContacts.isNotEmpty) {
        _emergencyContacts = savedContacts
            .whereType<Map<String, dynamic>>()
            .map(_EmergencyContact.fromMap)
            .toList();
      } else if ((saved['kin_name'] as String? ?? '').trim().isNotEmpty) {
        _emergencyContacts = <_EmergencyContact>[
          _EmergencyContact(
            id: 'legacy-primary',
            name: saved['kin_name'] as String? ?? '',
            relationship: saved['kin_relationship'] as String? ?? '',
            countryCode:
                saved['kin_country_code'] as String? ?? 'UG',
            dialCode: saved['kin_dial_code'] as String? ?? '+256',
            phone: saved['kin_phone'] as String? ?? '',
            email: saved['kin_email'] as String? ?? '',
          ),
        ];
      }
      final List<dynamic>? savedActions =
          saved['trigger_actions'] as List<dynamic>?;
      if (savedActions != null && savedActions.isNotEmpty) {
        _triggerActions = savedActions
            .whereType<Map<String, dynamic>>()
            .map(_TriggerAction.fromMap)
            .toList();
      }
      _pinController.text = saved['pin'] as String? ?? '';
      _pinDraft = saved['pin_draft'] as String? ?? _pinController.text;
      _profileSaved =
          saved['profile_saved'] as bool? ?? (_step >= 9);
      if (_step == 9 && !_profileSaved) {
        _step = 8;
      }
      _normalizeStep();
    });
  }

  Map<String, dynamic> _draftPayload() {
    return <String, dynamic>{
      'step': _step,
      'profile_saved': _profileSaved,
      'full_name': _fullNameController.text.trim(),
      'user_type': _selectedUserType,
      'frequency': _frequency,
      'grace_minutes': _graceMinutes,
      'grace_custom_mode': _graceCustomMode,
      'custom_grace_hours': _customGraceHours,
      'custom_grace_minutes': _customGraceMinutes,
      'checkin_hour': _checkinTime.hour,
      'checkin_minute': _checkinTime.minute,
      'kin_contacts': _emergencyContacts
          .asMap()
          .entries
          .map(
            (MapEntry<int, _EmergencyContact> entry) => entry.value.toMap(
              role: entry.key == 0 ? 'primary' : 'secondary',
            ),
          )
          .toList(),
      'trigger_actions': _triggerActions.map((a) => a.toMap()).toList(),
      'pin': _pinController.text.trim(),
      'pin_draft': _pinDraft,
    };
  }

  Future<void> _saveDraft() async {
    final Map<String, dynamic> draft = _draftPayload();
    try {
      await StorageService.instance.saveOnboardingDraft(draft);
    } catch (_) {
      // ignore draft save failures during hot reload
    }

    final UserModel? user = await AuthService.instance.resolveSessionUser();
    if (user != null) {
      unawaited(
        AuthService.instance.saveOnboardingDraft(
          uid: user.uid,
          step: _step,
          draft: draft,
        ),
      );
    }
  }

  Duration _frequencyToDuration(String value) {
    switch (value) {
      case 'Weekly':
        return const Duration(days: 7);
      case 'Monthly':
        return const Duration(days: 30);
      default:
        return const Duration(days: 1);
    }
  }

  int _snapGraceMinutes(int minutes) {
    int closest = _graceStepMinutes.first;
    int minDiff = (minutes - closest).abs();
    for (final int step in _graceStepMinutes) {
      final int diff = (minutes - step).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = step;
      }
    }
    return closest;
  }

  int get _graceSliderIndex {
    if (_graceCustomMode) {
      return -1;
    }
    final int index = _graceStepMinutes.indexOf(_graceMinutes);
    return index >= 0 ? index : _graceStepMinutes.indexOf(120);
  }

  String _formatGraceDuration(int minutes) {
    if (minutes < 60) {
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    if (mins == 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final String hourPart = hours == 1 ? '1 hour' : '$hours hours';
    final String minutePart = mins == 1 ? '1 minute' : '$mins minutes';
    return '$hourPart $minutePart';
  }

  String _graceSummaryText() {
    return 'We\'ll wait ${_formatGraceDuration(_graceMinutes)} before notifying your contacts';
  }

  void _syncCustomPartsFromMinutes() {
    _customGraceHours = _graceMinutes ~/ 60;
    _customGraceMinutes = _graceMinutes % 60;
  }

  void _setGraceMinutes(int minutes, {bool custom = false}) {
    setState(() {
      _graceMinutes = minutes.clamp(15, 1440);
      _graceCustomMode = custom;
      if (custom) {
        _syncCustomPartsFromMinutes();
      }
    });
    unawaited(_saveDraft());
  }

  void _setGraceFromSlider(int index) {
    setState(() {
      _graceMinutes = _graceStepMinutes[index];
      _graceCustomMode = false;
    });
    unawaited(_saveDraft());
  }

  void _setCustomGraceParts({int? hours, int? minutes}) {
    final int nextHours = hours ?? _customGraceHours;
    final int nextMinutes = minutes ?? _customGraceMinutes;
    final int total = (nextHours * 60) + nextMinutes;
    setState(() {
      _customGraceHours = nextHours.clamp(0, 24);
      _customGraceMinutes = _customMinuteOptions.contains(nextMinutes)
          ? nextMinutes
          : 0;
      _graceMinutes = total.clamp(15, 1440);
      _graceCustomMode = true;
    });
    unawaited(_saveDraft());
  }

  void _applyGracePreset(_GracePreset preset) {
    if (preset.isCustom) {
      _setGraceMinutes(_graceMinutes, custom: true);
      return;
    }
    _setGraceMinutes(preset.minutes ?? 120);
  }

  bool _isGracePresetSelected(_GracePreset preset) {
    if (preset.isCustom) {
      return _graceCustomMode;
    }
    return !_graceCustomMode && _graceMinutes == preset.minutes;
  }

  ({String value, String unit}) _graceDisplayParts() {
    if (_graceMinutes < 60) {
      return (value: '$_graceMinutes', unit: 'min');
    }
    if (_graceMinutes % 60 == 0) {
      final int hours = _graceMinutes ~/ 60;
      return (
        value: '$hours',
        unit: hours == 1 ? 'hour' : 'hours',
      );
    }
    return (
      value: '${_graceMinutes ~/ 60}h ${_graceMinutes % 60}m',
      unit: '',
    );
  }

  String? _migrateUserType(String? type) {
    switch (type) {
      case 'Elderly':
        return 'Living Alone';
      case 'Personal':
        return 'Other';
      default:
        return type;
    }
  }

  void _selectPersona(_PersonaOption option) {
    setState(() {
      _selectedUserType = option.id;
      _error = null;
      if (option.recommendedGraceHours != null) {
        _graceMinutes = option.recommendedGraceHours! * 60;
        _graceCustomMode = false;
      }
    });
    unawaited(_saveDraft());
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        if (_fullNameController.text.trim().isEmpty) {
          setState(() => _error = 'Enter your full name.');
          return false;
        }
        break;
      case 1:
        if (_selectedUserType == null) {
          setState(() => _error = 'Select the option that best describes you.');
          return false;
        }
        break;
      case 3:
        if (_graceMinutes < 15) {
          setState(() => _error = 'Grace period must be at least 15 minutes.');
          return false;
        }
        break;
      case 4:
        if (_emergencyContacts.isEmpty) {
          setState(() => _error = 'Add at least one emergency contact.');
          return false;
        }
        for (final _EmergencyContact contact in _emergencyContacts) {
          if (contact.name.trim().isEmpty ||
              contact.relationship.trim().isEmpty ||
              contact.phone.trim().isEmpty) {
            setState(
              () => _error = 'Each contact needs a name, relationship, and phone.',
            );
            return false;
          }
          if (PhoneNumberService.normalizeLocalToE164(
                rawInput: contact.phone.trim(),
                isoCode: contact.countryCode,
              ) ==
              null) {
            setState(
              () => _error =
                  'Use a valid local number for ${contact.name.trim().isEmpty ? 'each contact' : contact.name.trim()}.',
            );
            return false;
          }
        }
        break;
      case 5:
        if (_triggerActions.where((a) => a.enabled).isEmpty) {
          setState(() => _error = 'Enable at least one trigger action.');
          return false;
        }
        break;
      case 6:
        if (_pinController.text.trim().length != 4) {
          setState(() => _error = 'Enter a 4-digit cancel PIN.');
          return false;
        }
        break;
      case 7:
        if (_pinConfirmController.text.trim().length != 4) {
          setState(() => _error = 'Re-enter your 4-digit cancel PIN.');
          return false;
        }
        if (_pinConfirmController.text.trim() != _pinDraft) {
          setState(() => _error = 'PINs don\'t match. Try again.');
          return false;
        }
        break;
    }
    return true;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) {
      return;
    }
    setState(() {
      _error = null;
      if (_step == 6) {
        _pinDraft = _pinController.text.trim();
        _pinConfirmController.clear();
      }
      if (_step < _totalSteps - 1) {
        _step += 1;
      }
      _normalizeStep();
    });
    unawaited(_saveDraft());
  }

  bool get _canGoBack => _effectiveStep > 0 && !_saving;

  void _handleBack() {
    if (!_canGoBack) {
      if (_effectiveStep == 0 && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    _previousStep();
  }

  void _previousStep() {
    if (_step == 0) {
      return;
    }
    setState(() {
      _error = null;
      if (_step == 7) {
        _pinConfirmController.clear();
      }
      if (_step >= 8) {
        _profileSaved = false;
      }
      _step -= 1;
      _normalizeStep();
    });
    unawaited(_saveDraft());
  }

  Future<bool> _saveOnboardingProfile() async {
    final UserModel? user = await AuthService.instance.resolveSessionUser();
    if (user == null) {
      if (mounted) {
        setState(
          () => _error =
              'Session expired. Please log in again and retry setup.',
        );
      }
      return false;
    }

    try {
      final Duration checkInPeriod = _frequencyToDuration(_frequency);
      final Duration gracePeriod = Duration(minutes: _graceMinutes);
      final DateTime now = DateTime.now();
      final _EmergencyContact primaryContact = _emergencyContacts.first;
      final String? kinPhoneForApi = PhoneNumberService.toLocalDigitsForApi(
        rawInput: primaryContact.phone.trim(),
        isoCode: primaryContact.countryCode,
      );
      if (kinPhoneForApi == null) {
        if (mounted) {
          setState(
            () => _error =
                'Primary contact phone is invalid for the selected country.',
          );
        }
        return false;
      }
      final List<Map<String, dynamic>> contactsPayload = _emergencyContacts
          .asMap()
          .entries
          .map(
            (MapEntry<int, _EmergencyContact> entry) => entry.value.toMap(
              role: entry.key == 0 ? 'primary' : 'secondary',
            ),
          )
          .toList();
      final String checkinTimeText =
          '${_checkinTime.hour.toString().padLeft(2, '0')}:${_checkinTime.minute.toString().padLeft(2, '0')}';
      final String timezone = await _deviceTimezone();

      final bool saved = await AuthService.instance.createOrUpdateUser(
        uid: user.uid,
        phoneNumber: user.phoneNumber ?? '',
        extra: <String, dynamic>{
          'onboarding_completed': true,
          'email': user.email,
          'full_name': _fullNameController.text.trim(),
          'user_type': _selectedUserType,
          'checkin_frequency': _frequency,
          'grace_period_hours': (_graceMinutes / 60).ceil(),
          'grace_period_minutes': _graceMinutes,
          'checkin_time': checkinTimeText,
          'timezone': timezone,
          'emergency_contact_name': primaryContact.name.trim(),
          'emergency_contact_relationship': primaryContact.relationship.trim(),
          'emergency_contact_country_code': primaryContact.countryCode,
          'emergency_contact_phone': kinPhoneForApi,
          'emergency_contact_email': primaryContact.email.trim(),
          'emergency_contacts_json': jsonEncode(contactsPayload),
          'trigger_actions_json': jsonEncode(
            _triggerActions.where((a) => a.enabled).map((a) => a.toMap()).toList(),
          ),
          'pin': _pinController.text.trim(),
          'last_check_in_at': now.toIso8601String(),
          'max_retry_attempts': 3,
        },
      );
      if (!saved) {
        if (mounted) {
          setState(
            () => _error =
                AuthService.instance.lastProfileSaveError ??
                'Could not save your profile to the server. Check connection and try again.',
          );
        }
        return false;
      }

      await StorageService.instance.savePeriodDurations(
        checkInPeriod: checkInPeriod,
        gracePeriod: gracePeriod,
      );
      await StorageService.instance.saveSchedule(
        checkinTime: checkinTimeText,
        checkinFrequency: _frequency,
      );
      await StorageService.instance.saveLastCheckIn(now);
      await AlarmScheduler.instance.ensureAlarmsScheduled();
      await PushCheckinService.instance.registerTokenIfLoggedIn();

      await SafetyService.instance.logTimelineEvent(
        uid: user.uid,
        eventType: 'onboarding_completed',
        status: 'success',
        payload: <String, dynamic>{
          'checkin_frequency': _frequency,
          'checkin_time': checkinTimeText,
          'grace_period_hours': (_graceMinutes / 60).ceil(),
          'grace_period_minutes': _graceMinutes,
        },
      );
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Failed to save onboarding. Check connection and retry.',
        );
      }
      return false;
    }
  }

  Future<void> _runOnboardingTest() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (!_profileSaved) {
        final bool saved = await _saveOnboardingProfile();
        if (!saved) {
          return;
        }
        _profileSaved = true;
      }

      try {
        await NotificationService.instance.showOnboardingTestNotification();
      } catch (_) {
        // Non-fatal — profile is saved; user can still continue.
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _step = 9;
        _error = null;
        _normalizeStep();
      });
      unawaited(_saveDraft());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _goToDashboard() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (!_profileSaved) {
        final bool saved = await _saveOnboardingProfile();
        if (!saved) {
          return;
        }
        _profileSaved = true;
      }

      if (!mounted) {
        return;
      }

      final UserModel? sessionUser =
          await AuthService.instance.resolveSessionUser();
      await StorageService.instance.clearOnboardingDraft();
      if (sessionUser != null) {
        await AuthService.instance.clearOnboardingDraftOnServer(sessionUser.uid);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AlarmSetupScreen()),
        (_) => false,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String get _currentStepTag => _stepTags[_effectiveStep];

  String _formatCheckinTimeLabel() {
    final TimeOfDay time = _checkinTime;
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _gracePeriodChecklistLabel() {
    if (_graceMinutes < 60) {
      return _graceMinutes == 1 ? '1 minute' : '$_graceMinutes minutes';
    }
    if (_graceMinutes % 60 == 0) {
      final int hours = _graceMinutes ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return _formatGraceDuration(_graceMinutes);
  }

  String _gracePeriodPillHighlight() {
    if (_graceMinutes < 60) {
      return '${_graceMinutes}min';
    }
    if (_graceMinutes % 60 == 0) {
      return '${_graceMinutes ~/ 60}hr';
    }
    return _formatGraceDuration(_graceMinutes);
  }

  int get _enabledTriggerActionCount =>
      _triggerActions.where((a) => a.enabled).length;

  static const List<String> _keypadLetters = <String>[
    '', // 0
    '', // 1
    'ABC', // 2
    'DEF', // 3
    'GHI', // 4
    'JKL', // 5
    'MNO', // 6
    'PQRS', // 7
    'TUV', // 8
    'WXYZ', // 9
  ];

  TextEditingController get _activePinController =>
      _effectiveStep == 7 ? _pinConfirmController : _pinController;

  void _setActivePinValue(String value) {
    _activePinController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _appendPinDigit(String digit) {
    if (_activePinController.text.length >= 4) {
      return;
    }
    setState(() {
      _setActivePinValue('${_activePinController.text}$digit');
      _error = null;
    });
    if (_effectiveStep == 6) {
      unawaited(_saveDraft());
    }
  }

  void _clearPin() {
    setState(() {
      _setActivePinValue('');
      _error = null;
    });
    if (_effectiveStep == 6) {
      unawaited(_saveDraft());
    }
  }

  void _backspacePin() {
    final String value = _activePinController.text;
    if (value.isEmpty) {
      return;
    }
    setState(() {
      _setActivePinValue(value.substring(0, value.length - 1));
      _error = null;
    });
    if (_effectiveStep == 6) {
      unawaited(_saveDraft());
    }
  }

  Future<String> _deviceTimezone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> _pickCheckinTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkinTime,
    );
    if (picked != null) {
      setState(() => _checkinTime = picked);
      unawaited(_saveDraft());
    }
  }

  @override
  void dispose() {
    unawaited(_saveDraft());
    _fullNameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_step != _effectiveStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step != _effectiveStep) {
          setState(_normalizeStep);
        }
      });
    }

    final int step = _effectiveStep;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _background,
      ),
      child: Theme(
        data: AppTheme.darkTheme.copyWith(
          scaffoldBackgroundColor: _background,
        ),
        child: PopScope(
          canPop: _canGoBack
              ? false
              : (_effectiveStep == 0 && Navigator.of(context).canPop()),
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop || !_canGoBack) {
              return;
            }
            _previousStep();
          },
          child: Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _buildProfileProgressHeader(),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                          child: step == 9
                              ? const SizedBox.shrink()
                              : _buildProfileStepHeader(),
                        ),
                      ),
                      if (step == 1)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildPersonaGrid(),
                          ),
                        )
                      else if (step == 2)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildFrequencyStepBody(),
                          ),
                        )
                      else if (step == 3)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildGraceStepBody(),
                          ),
                        )
                      else if (step == 4)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildContactsStepBody(),
                          ),
                        )
                      else if (step == 5)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildTriggerActionsStepBody(),
                          ),
                        )
                      else if (step == 6)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildCancelPinStepBody(),
                          ),
                        )
                      else if (step == 7)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildConfirmPinStepBody(),
                          ),
                        )
                      else if (step == 8)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildTestCheckStepBody(),
                          ),
                        )
                      else if (step == 9)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildCelebrationStepBody(),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _buildProfileStepBody(),
                          ),
                        ),
                      if (_error != null && step <= _totalSteps - 1)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          sliver: SliverToBoxAdapter(child: _buildErrorBanner()),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: _buildBottomActions(),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildProfileProgressHeader() {
    final int step = _effectiveStep;
    final double progress = (step + 1) / _totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (step > 0) ...<Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _canGoBack ? _handleBack : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: Colors.white70,
              style: IconButton.styleFrom(
                backgroundColor: _cardBackground,
                minimumSize: const Size(40, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'SCREEN ${step + 1} OF $_totalSteps — $_currentStepTag',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStepHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _titleForStep(),
          style: const TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _subtitleForStep(),
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStepBody() {
    if (_effectiveStep != 0) {
      return const SizedBox.shrink();
    }

    return Theme(
      data: AppTheme.darkTheme,
      child: InputField(
        controller: _fullNameController,
        label: 'Your full name',
      ),
    );
  }

  Widget _buildPersonaGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: _personaOptions.length,
      itemBuilder: (BuildContext context, int index) {
        final _PersonaOption option = _personaOptions[index];
        final bool selected = _selectedUserType == option.id;
        return GestureDetector(
          onTap: () => _selectPersona(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? _accent
                    : Colors.white.withValues(alpha: 0.06),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(option.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 10),
                Text(
                  option.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    option.description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                ),
                Text(
                  option.footerText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrequencyStepBody() {
    return Column(
      children: <Widget>[
        ..._frequencyOptions.map(_frequencyCard),
        const SizedBox(height: 16),
        _scheduleTile(
          icon: Icons.schedule_rounded,
          iconColor: _accent,
          title: 'Check-in time',
          value: _checkinTime.format(context),
          onTap: _pickCheckinTime,
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You can always change this later. If you miss a check-in, we\'ll wait through your grace period before alerting anyone.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _frequencyCard(_FrequencyOption option) {
    final bool selected = _frequency == option.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          setState(() => _frequency = option.id);
          unawaited(_saveDraft());
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _accent
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.calendar_month_rounded,
                color: selected ? _accent : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          option.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (option.recommended) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Recommended',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? _accent : Colors.white30,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGraceStepBody() {
    final ({String value, String unit}) display = _graceDisplayParts();
    final int sliderIndex = _graceSliderIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    display.value,
                    style: const TextStyle(
                      fontSize: 56,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                  if (display.unit.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        display.unit,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _graceSummaryText(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (!_graceCustomMode) ...<Widget>[
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Colors.white,
              overlayColor: _accent.withValues(alpha: 0.15),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: sliderIndex.toDouble(),
              min: 0,
              max: (_graceStepMinutes.length - 1).toDouble(),
              divisions: _graceStepMinutes.length - 1,
              onChanged: (double value) =>
                  _setGraceFromSlider(value.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '15 min',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '6 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '12 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                Text(
                  '24 hrs',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ] else
          _buildCustomGracePicker(),
        const SizedBox(height: 24),
        Text(
          'SMART PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: _gracePresets.length,
          itemBuilder: (BuildContext context, int index) {
            final _GracePreset preset = _gracePresets[index];
            final bool selected = _isGracePresetSelected(preset);
            return GestureDetector(
              onTap: () => _applyGracePreset(preset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? _accent
                        : Colors.white.withValues(alpha: 0.06),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(preset.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 8),
                    Text(
                      preset.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      preset.durationLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCustomGracePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Custom grace period',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hours',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _customGraceHours,
                          isExpanded: true,
                          dropdownColor: _cardBackground,
                          items: List<DropdownMenuItem<int>>.generate(
                            25,
                            (int index) => DropdownMenuItem<int>(
                              value: index,
                              child: Text('$index'),
                            ),
                          ),
                          onChanged: (int? value) {
                            if (value == null) return;
                            _setCustomGraceParts(hours: value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Minutes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _customGraceMinutes,
                          isExpanded: true,
                          dropdownColor: _cardBackground,
                          items: _customMinuteOptions
                              .map(
                                (int value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (int? value) {
                            if (value == null) return;
                            _setCustomGraceParts(minutes: value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Minimum 15 minutes. Maximum 24 hours.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContactEditor({int? index}) async {
    final bool editing = index != null;
    final _EmergencyContact seed = editing
        ? _emergencyContacts[index]
        : _EmergencyContact(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '',
            relationship: '',
            countryCode: 'UG',
            dialCode: '+256',
            phone: '',
          );

    final TextEditingController nameController =
        TextEditingController(text: seed.name);
    final TextEditingController relationshipController =
        TextEditingController(text: seed.relationship);
    final TextEditingController phoneController =
        TextEditingController(text: seed.phone);
    final TextEditingController emailController =
        TextEditingController(text: seed.email);
    String countryCode = seed.countryCode;
    String dialCode = seed.dialCode;
    String? formError;

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      editing ? 'Edit contact' : 'Add emergency contact',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Theme(
                      data: AppTheme.darkTheme,
                      child: InputField(
                        controller: nameController,
                        label: 'Full name',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Theme(
                      data: AppTheme.darkTheme,
                      child: InputField(
                        controller: relationshipController,
                        label: 'Relationship',
                        hint: 'Family, Colleague, Friend',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _scheduleTile(
                      icon: Icons.public_rounded,
                      iconColor: const Color(0xFFE6A85C),
                      title: 'Country',
                      value: '$countryCode ($dialCode)',
                      onTap: () {
                        showCountryPicker(
                          context: context,
                          onSelect: (Country country) {
                            setSheetState(() {
                              countryCode = country.countryCode;
                              dialCode = '+${country.phoneCode}';
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Theme(
                      data: AppTheme.darkTheme,
                      child: InputField(
                        controller: phoneController,
                        label: 'Phone (local number)',
                        hint: 'e.g. 779697569',
                        keyboardType: TextInputType.phone,
                        maxLength: 15,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Theme(
                      data: AppTheme.darkTheme,
                      child: InputField(
                        controller: emailController,
                        label: 'Email (optional)',
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    if (formError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        formError!,
                        style: const TextStyle(
                          color: AppTheme.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          if (nameController.text.trim().isEmpty ||
                              relationshipController.text.trim().isEmpty ||
                              phoneController.text.trim().isEmpty) {
                            setSheetState(
                              () => formError =
                                  'Name, relationship, and phone are required.',
                            );
                            return;
                          }
                          if (PhoneNumberService.normalizeLocalToE164(
                                rawInput: phoneController.text.trim(),
                                isoCode: countryCode,
                              ) ==
                              null) {
                            setSheetState(
                              () => formError =
                                  'Use a valid local number for the selected country.',
                            );
                            return;
                          }
                          Navigator.of(context).pop(true);
                        },
                        child: Text(editing ? 'Save contact' : 'Add contact'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      nameController.dispose();
      relationshipController.dispose();
      phoneController.dispose();
      emailController.dispose();
      return;
    }

    final _EmergencyContact contact = _EmergencyContact(
      id: seed.id,
      name: nameController.text.trim(),
      relationship: relationshipController.text.trim(),
      countryCode: countryCode,
      dialCode: dialCode,
      phone: phoneController.text.trim(),
      email: emailController.text.trim(),
    );

    nameController.dispose();
    relationshipController.dispose();
    phoneController.dispose();
    emailController.dispose();

    setState(() {
      _error = null;
      if (index != null) {
        _emergencyContacts[index] = contact;
      } else {
        _emergencyContacts.add(contact);
      }
    });
    unawaited(_saveDraft());
  }

  void _removeContact(int index) {
    if (_emergencyContacts.length <= 1) {
      setState(
        () => _error = 'Keep at least one emergency contact.',
      );
      return;
    }
    setState(() {
      _emergencyContacts.removeAt(index);
      _error = null;
    });
    unawaited(_saveDraft());
  }

  Color _contactAvatarColor(int index) {
    if (index == 0) {
      return _accent;
    }
    return const Color(0xFF1F6F4A);
  }

  Widget _buildContactsStepBody() {
    return Column(
      children: <Widget>[
        if (_emergencyContacts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              'Add someone who should be alerted if you miss a check-in.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.58),
              ),
            ),
          )
        else
          ...List<Widget>.generate(_emergencyContacts.length, (int index) {
            final _EmergencyContact contact = _emergencyContacts[index];
            final bool isPrimary = index == 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showContactEditor(index: index),
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _contactAvatarColor(index),
                          child: Text(
                            contact.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                contact.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${contact.displayPhone} · ${contact.relationship}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.52),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isPrimary
                                      ? _accent.withValues(alpha: 0.15)
                                      : const Color(0xFFFBBF24)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isPrimary ? 'Primary' : 'Secondary',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isPrimary
                                        ? _accent
                                        : const Color(0xFFFBBF24),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _removeContact(index),
                          icon: const Icon(Icons.close_rounded),
                          color: AppTheme.secondary,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppTheme.secondary.withValues(alpha: 0.12),
                            minimumSize: const Size(36, 36),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _showContactEditor(),
          icon: const Icon(Icons.add_rounded, color: _accent),
          label: const Text(
            'Add another contact',
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(
              color: _accent.withValues(alpha: 0.55),
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your contacts receive a one-time opt-in message. They can remove themselves at any time. We never share their details.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickActionDelay(int index) async {
    final _TriggerAction action = _triggerActions[index];
    final int? selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Action delay',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ..._actionDelayOptions.map((int minutes) {
                  final String label = minutes == 0
                      ? (index == 0 ? 'Immediate' : '+0 min')
                      : minutes < 60
                          ? '+$minutes min'
                          : minutes % 60 == 0
                              ? '+${minutes ~/ 60} hrs'
                              : '+$minutes min';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label, style: const TextStyle(color: Colors.white)),
                    trailing: action.delayMinutes == minutes
                        ? const Icon(Icons.check_rounded, color: _accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(minutes),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _triggerActions[index].delayMinutes = selected;
      _error = null;
    });
    unawaited(_saveDraft());
  }

  void _addOptionalTriggerAction() {
    final Set<String> existingTypes =
        _triggerActions.map((a) => a.type).toSet();
    final List<_TriggerAction> available = _optionalTriggerActions()
        .where((a) => !existingTypes.contains(a.type))
        .toList();
    if (available.isEmpty) {
      setState(
        () => _error = 'All optional actions are already in your list.',
      );
      return;
    }
    setState(() {
      _triggerActions.add(
        _TriggerAction(
          id: '${available.first.type}-${DateTime.now().millisecondsSinceEpoch}',
          type: available.first.type,
          title: available.first.title,
          description: available.first.description,
          emoji: available.first.emoji,
          delayMinutes: available.first.delayMinutes,
        ),
      );
      _error = null;
    });
    unawaited(_saveDraft());
  }

  IconData _triggerActionIcon(String type) {
    switch (type) {
      case 'sms':
        return Icons.sms_outlined;
      case 'gps':
        return Icons.my_location_rounded;
      case 'email':
        return Icons.mail_outline_rounded;
      case 'document_vault':
        return Icons.description_outlined;
      case 'whatsapp':
        return Icons.chat_bubble_outline_rounded;
      case 'call_retry':
        return Icons.phone_in_talk_outlined;
      default:
        return Icons.bolt_rounded;
    }
  }

  Widget _buildTriggerActionCard(int index) {
    final _TriggerAction action = _triggerActions[index];
    final bool isFirst = index == 0;
    return Container(
      key: ValueKey<String>(action.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: action.enabled ? 0.14 : 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _triggerActionIcon(action.type),
              color: action.enabled ? _accent : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  action.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: action.enabled ? Colors.white : Colors.white38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.52),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _pickActionDelay(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                action.delayLabel(isFirst: isFirst),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFBBF24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerActionsStepBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _triggerActions.length,
          onReorder: (int oldIndex, int newIndex) {
            setState(() {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final _TriggerAction item = _triggerActions.removeAt(oldIndex);
              _triggerActions.insert(newIndex, item);
              _error = null;
            });
            unawaited(_saveDraft());
          },
          itemBuilder: (BuildContext context, int index) {
            return _buildTriggerActionCard(index);
          },
        ),
        OutlinedButton.icon(
          onPressed: _addOptionalTriggerAction,
          icon: const Icon(Icons.add_rounded, color: _accent),
          label: const Text(
            'Add another action',
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(
              color: _accent.withValues(alpha: 0.55),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Drag actions to reorder. Tap the delay badge to change timing.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.secondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    final int step = _effectiveStep;
    final bool isTestStep = step == 8;
    final bool isCelebrationStep = step == 9;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving
            ? null
            : (isCelebrationStep
                ? _goToDashboard
                : (isTestStep ? _runOnboardingTest : _nextStep)),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _saving
                ? Colors.white.withValues(alpha: 0.08)
                : (isTestStep ? _testGold : _accent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: isTestStep ? _testGoldText : Colors.white,
                    ),
                  )
                : Text(
                    isCelebrationStep
                        ? 'Go to my dashboard  →'
                        : (isTestStep ? 'Run My Test  →' : 'Continue  →'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isTestStep ? _testGoldText : Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _scheduleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleForStep() {
    switch (_effectiveStep) {
      case 0:
        return 'What\'s your name?';
      case 1:
        return 'Which best describes you?';
      case 2:
        return 'How often should we check in?';
      case 3:
        return 'How long should we wait?';
      case 4:
        return 'Who should we alert?';
      case 5:
        return 'What should we do?';
      case 6:
        return 'Set your cancel PIN';
      case 7:
        return 'Confirm your cancel PIN';
      case 8:
        return 'Let\'s make sure it works';
      default:
        return 'Safety Setup';
    }
  }

  String _subtitleForStep() {
    switch (_effectiveStep) {
      case 0:
        return 'This helps your contacts know who they\'re checking on.';
      case 1:
        return 'We\'ll pre-fill your settings to match. You can always change them.';
      case 2:
        return 'We\'ll send you a quick notification at your chosen time.';
      case 3:
        return 'If you miss your check-in, we wait this long before alerting your contacts.';
      case 4:
        return 'These people will be contacted if you don\'t check in. They can opt out at any time.';
      case 5:
        return 'When grace period expires, these actions fire in order.';
      case 6:
        return 'If you miss a check-in, tap this PIN from the notification to cancel the alert instantly — no need to open the app.';
      case 7:
        return 'Enter the same PIN again so we know you\'ve got it.';
      case 8:
        return 'A TEST notification — clearly marked. No one panics.';
      default:
        return '';
    }
  }

  Widget _buildSetupChecklistItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: _accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestNotificationPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A4A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF5C9CE6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: Color(0xFF5C9CE6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Safebangle • SafeCheck',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _testGold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TEST ONLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: _testGoldText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Are you okay?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hi — Just your daily SafeCheck. Tap to confirm you\'re okay.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCheckStepBody() {
    final int contactCount = _emergencyContacts.length;
    final String contactLabel =
        contactCount == 1 ? '1 emergency contact' : '$contactCount emergency contacts';
    final int actionCount = _enabledTriggerActionCount;
    final String actionLabel =
        actionCount == 1 ? '1 trigger action' : '$actionCount trigger actions';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildTestNotificationPreview(),
        const SizedBox(height: 28),
        _buildSetupChecklistItem(
          '$_frequency check-in • ${_formatCheckinTimeLabel()}',
        ),
        _buildSetupChecklistItem(
          'Grace period • ${_gracePeriodChecklistLabel()}',
        ),
        _buildSetupChecklistItem(contactLabel),
        _buildSetupChecklistItem(actionLabel),
        _buildSetupChecklistItem('Cancel PIN set'),
      ],
    );
  }

  Widget _summaryPill({
    required String highlight,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          children: <InlineSpan>[
            TextSpan(
              text: highlight,
              style: const TextStyle(color: _accent),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBraceletUpsellCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Safebangle bracelet pairing is coming soon.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF9B7EDE).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('⌚', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Add real-time protection',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _testGold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pair with Safebangle bracelet',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.48),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationStepBody() {
    final int contactCount = _emergencyContacts.length;
    final int actionCount = _enabledTriggerActionCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(height: 16),
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_outlined,
            size: 46,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 34,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            children: const <InlineSpan>[
              TextSpan(text: 'You Are '),
              TextSpan(
                text: 'Protected.',
                style: TextStyle(
                  color: _accent,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SafeCheck is live. Someone is always checking on you — even when you can\'t ask for it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: <Widget>[
            _summaryPill(highlight: _frequency, label: 'check-in'),
            _summaryPill(
              highlight: _gracePeriodPillHighlight(),
              label: 'grace',
            ),
            _summaryPill(highlight: '$contactCount', label: 'contacts'),
            _summaryPill(highlight: '$actionCount', label: 'actions'),
          ],
        ),
        const SizedBox(height: 28),
        _buildBraceletUpsellCard(),
      ],
    );
  }

  Widget _buildPinBoxes() {
    final String pin = _activePinController.text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (int index) {
        final bool filled = index < pin.length;
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filled
                    ? _accent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.12),
                width: filled ? 1.5 : 1,
              ),
            ),
            child: Text(
              filled ? pin[index] : '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypadButton({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saving ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 64,
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildNumericKeypad() {
    Widget digitButton(int digit) {
      return _buildKeypadButton(
        onTap: () => _appendPinDigit('$digit'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '$digit',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            if (digit < _keypadLetters.length &&
                _keypadLetters[digit].isNotEmpty)
              Text(
                _keypadLetters[digit],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.38),
                  height: 1.2,
                ),
              ),
          ],
        ),
      );
    }

    Widget keypadRow(List<Widget> buttons) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < buttons.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              buttons[i],
            ],
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        keypadRow(<Widget>[digitButton(1), digitButton(2), digitButton(3)]),
        keypadRow(<Widget>[digitButton(4), digitButton(5), digitButton(6)]),
        keypadRow(<Widget>[digitButton(7), digitButton(8), digitButton(9)]),
        keypadRow(<Widget>[
          _buildKeypadButton(
            onTap: _clearPin,
            child: Text(
              'Clear',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          digitButton(0),
          _buildKeypadButton(
            onTap: _backspacePin,
            child: Icon(
              Icons.backspace_outlined,
              size: 22,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildPinEntryStepBody({required String tipText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 28),
        _buildPinBoxes(),
        const SizedBox(height: 32),
        _buildNumericKeypad(),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tipText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCancelPinStepBody() {
    return _buildPinEntryStepBody(
      tipText:
          'Choose something memorable under pressure — like a birthday or favourite number. You can change it anytime in Settings.',
    );
  }

  Widget _buildConfirmPinStepBody() {
    return _buildPinEntryStepBody(
      tipText:
          'Must match the PIN you just entered. You\'ll use this to cancel alerts from notifications.',
    );
  }
}
