import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/screens/alarm_setup_screen.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';
import 'package:safecheck/widgets/auth_step_indicator.dart';
import 'package:safecheck/widgets/input_field.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  final List<String> _userTypes = <String>[
    'Field Worker',
    'Elderly',
    'Traveller',
    'Personal',
  ];
  String? _selectedUserType;
  String _frequency = 'Daily';
  int _graceHours = 2;
  TimeOfDay _checkinTime = const TimeOfDay(hour: 18, minute: 0);
  String _nextOfKinCountryCode = 'UG';
  String _nextOfKinDialCode = '+256';

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactRelationshipController =
      TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();
  final TextEditingController _contactEmailController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadDraft());
  }

  Future<void> _loadDraft() async {
    Map<String, dynamic>? draft;
    try {
      draft = await StorageService.instance.getOnboardingDraft();
    } catch (_) {
      // Can happen after hot reload when StorageService was updated in code.
      return;
    }
    if (draft == null || !mounted) {
      return;
    }
    final Map<String, dynamic> saved = draft;
    setState(() {
      _step = saved['step'] as int? ?? _step;
      _fullNameController.text = saved['full_name'] as String? ?? '';
      _selectedUserType = saved['user_type'] as String?;
      _frequency = saved['frequency'] as String? ?? _frequency;
      _graceHours = saved['grace_hours'] as int? ?? _graceHours;
      final int? hour = saved['checkin_hour'] as int?;
      final int? minute = saved['checkin_minute'] as int?;
      if (hour != null && minute != null) {
        _checkinTime = TimeOfDay(hour: hour, minute: minute);
      }
      _nextOfKinCountryCode =
          saved['kin_country_code'] as String? ?? _nextOfKinCountryCode;
      _nextOfKinDialCode =
          saved['kin_dial_code'] as String? ?? _nextOfKinDialCode;
      _contactNameController.text = saved['kin_name'] as String? ?? '';
      _contactRelationshipController.text =
          saved['kin_relationship'] as String? ?? '';
      _contactPhoneController.text = saved['kin_phone'] as String? ?? '';
      _contactEmailController.text = saved['kin_email'] as String? ?? '';
      _pinController.text = saved['pin'] as String? ?? '';
    });
  }

  Future<void> _saveDraft() async {
    try {
      await StorageService.instance.saveOnboardingDraft(<String, dynamic>{
        'step': _step,
        'full_name': _fullNameController.text.trim(),
        'user_type': _selectedUserType,
        'frequency': _frequency,
        'grace_hours': _graceHours,
        'checkin_hour': _checkinTime.hour,
        'checkin_minute': _checkinTime.minute,
        'kin_country_code': _nextOfKinCountryCode,
        'kin_dial_code': _nextOfKinDialCode,
        'kin_name': _contactNameController.text.trim(),
        'kin_relationship': _contactRelationshipController.text.trim(),
        'kin_phone': _contactPhoneController.text.trim(),
        'kin_email': _contactEmailController.text.trim(),
        'pin': _pinController.text.trim(),
      });
    } catch (_) {
      // ignore draft save failures during hot reload
    }
  }

  Duration _frequencyToDuration(String value) {
    if (value == 'Weekly') {
      return const Duration(days: 7);
    }
    return const Duration(days: 1);
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        if (_fullNameController.text.trim().isEmpty) {
          setState(() => _error = 'Enter your full name.');
          return false;
        }
        if (_selectedUserType == null) {
          setState(() => _error = 'Select a user type.');
          return false;
        }
        break;
      case 2:
        final String? normalizedNextOfKinPhone =
            PhoneNumberService.normalizeLocalToE164(
          rawInput: _contactPhoneController.text.trim(),
          isoCode: _nextOfKinCountryCode,
        );
        if (_contactNameController.text.trim().isEmpty ||
            _contactRelationshipController.text.trim().isEmpty ||
            _contactPhoneController.text.trim().isEmpty ||
            _contactEmailController.text.trim().isEmpty) {
          setState(() => _error = 'Complete all next-of-kin fields.');
          return false;
        }
        if (normalizedNextOfKinPhone == null) {
          setState(
            () => _error = 'Use a valid local number for the selected country.',
          );
          return false;
        }
        break;
      case 3:
        if (_pinController.text.trim().length != 4) {
          setState(() => _error = 'Set a 4-digit PIN.');
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
      if (_step < 3) {
        _step += 1;
      }
    });
    unawaited(_saveDraft());
  }

  void _previousStep() {
    if (_step == 0) {
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
    unawaited(_saveDraft());
  }

  Future<void> _completeOnboarding() async {
    if (!_validateCurrentStep()) {
      return;
    }

    final UserModel? user = await AuthService.instance.resolveSessionUser();
    if (user == null) {
      setState(
        () => _error = 'Session expired. Please log in again and retry setup.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Duration checkInPeriod = _frequencyToDuration(_frequency);
      final Duration gracePeriod = Duration(hours: _graceHours);
      final DateTime now = DateTime.now();
      final String? kinPhoneForApi = PhoneNumberService.toLocalDigitsForApi(
        rawInput: _contactPhoneController.text.trim(),
        isoCode: _nextOfKinCountryCode,
      );
      if (kinPhoneForApi == null) {
        setState(
          () => _error =
              'Next-of-kin phone is invalid for the selected country.',
        );
        return;
      }
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
          'grace_period_hours': _graceHours,
          'checkin_time': checkinTimeText,
          'timezone': timezone,
          'emergency_contact_name': _contactNameController.text.trim(),
          'emergency_contact_relationship': _contactRelationshipController.text
              .trim(),
          'emergency_contact_country_code': _nextOfKinCountryCode,
          'emergency_contact_phone': kinPhoneForApi,
          'emergency_contact_email': _contactEmailController.text.trim(),
          'pin': _pinController.text.trim(),
          'last_check_in_at': now.toIso8601String(),
          'max_retry_attempts': 3,
        },
      );
      if (!saved) {
        setState(
          () => _error =
              AuthService.instance.lastProfileSaveError ??
              'Could not save your profile to the server. Check connection and try again.',
        );
        return;
      }

      await StorageService.instance.clearOnboardingDraft();

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
          'grace_period_hours': _graceHours,
        },
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AlarmSetupScreen()),
        (_) => false,
      );
    } catch (_) {
      setState(
        () => _error = 'Failed to save onboarding. Check connection and retry.',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _graceChip(int hours) {
    final bool selected = _graceHours == hours;
    return GestureDetector(
      onTap: () => setState(() => _graceHours = hours),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : const Color(0xFF141A22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          '${hours}h',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  IconData _iconForStep() {
    switch (_step) {
      case 0:
        return Icons.person_outline_rounded;
      case 1:
        return Icons.schedule_rounded;
      case 2:
        return Icons.family_restroom_rounded;
      case 3:
        return Icons.lock_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  IconData _iconForUserType(String type) {
    switch (type) {
      case 'Field Worker':
        return Icons.engineering_rounded;
      case 'Elderly':
        return Icons.elderly_rounded;
      case 'Traveller':
        return Icons.flight_rounded;
      default:
        return Icons.person_rounded;
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
    _contactNameController.dispose();
    _contactRelationshipController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            child: Column(
              children: <Widget>[
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const AppLogo(height: 32),
                              const SizedBox(height: 24),
                              AuthStepIndicator(
                                currentStep: _step + 1,
                                totalSteps: 4,
                                labels: const <String>[
                                  'Profile',
                                  'Schedule',
                                  'Contact',
                                  'PIN',
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: _buildStepHeader(),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _buildStepCard(),
                        ),
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
    );
  }

  Widget _buildStepHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_iconForStep(), color: AppTheme.primary, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _titleForStep(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _subtitleForStep(),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141A22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepBody(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Row(
      children: <Widget>[
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : _previousStep,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Back'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          flex: _step > 0 ? 2 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _saving
                  ? null
                  : (_step == 3 ? _completeOnboarding : _nextStep),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: _saving
                      ? null
                      : const LinearGradient(
                          colors: <Color>[
                            Color(0xFF1F6F8B),
                            Color(0xFF2A8FAF),
                          ],
                        ),
                  color: _saving
                      ? Colors.white.withValues(alpha: 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _step == 3 ? 'Finish setup' : 'Continue',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _userTypeCard(String type) {
    final bool selected = _selectedUserType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedUserType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : const Color(0xFF0A0F14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              _iconForUserType(type),
              color: selected ? AppTheme.primary : Colors.white54,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                type,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
          ],
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
            color: const Color(0xFF0A0F14),
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
    switch (_step) {
      case 0:
        return 'About You';
      case 1:
        return 'Check-in Schedule';
      case 2:
        return 'Next of Kin';
      case 3:
        return 'Security';
      default:
        return 'Safety Setup';
    }
  }

  String _subtitleForStep() {
    switch (_step) {
      case 0:
        return 'Tell us who this safety profile is for.';
      case 1:
        return 'Choose how and when SafeCheck should call you.';
      case 2:
        return 'Who should we alert if you miss check-ins?';
      case 3:
        return 'Set your 4-digit PIN and finish setup.';
      default:
        return '';
    }
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Theme(
              data: AppTheme.darkTheme,
              child: InputField(
                controller: _fullNameController,
                label: 'Your full name',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Profile type',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            ..._userTypes.map(_userTypeCard),
          ],
        );
      case 1:
        return Column(
          children: <Widget>[
            _scheduleTile(
              icon: Icons.repeat_rounded,
              iconColor: const Color(0xFF5C9CE6),
              title: 'Check-in frequency',
              value: _frequency,
              onTap: () => setState(
                () => _frequency = _frequency == 'Daily' ? 'Weekly' : 'Daily',
              ),
              trailing: Switch(
                value: _frequency == 'Daily',
                activeThumbColor: Colors.white,
                activeTrackColor: AppTheme.primary,
                onChanged: (bool value) =>
                    setState(() => _frequency = value ? 'Daily' : 'Weekly'),
              ),
            ),
            const SizedBox(height: 10),
            _scheduleTile(
              icon: Icons.schedule_rounded,
              iconColor: AppTheme.primary,
              title: 'Scheduled call time',
              value: _checkinTime.format(context),
              onTap: _pickCheckinTime,
            ),
            const SizedBox(height: 20),
            Text(
              'Grace window after missed call',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How long before we alert your next of kin',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _graceChip(2),
                const SizedBox(width: 10),
                _graceChip(3),
                const SizedBox(width: 10),
                _graceChip(6),
              ],
            ),
          ],
        );
      case 2:
        return Column(
          children: <Widget>[
            Theme(
              data: AppTheme.darkTheme,
              child: InputField(
                controller: _contactNameController,
                label: 'Next of kin name',
              ),
            ),
            const SizedBox(height: 14),
            Theme(
              data: AppTheme.darkTheme,
              child: InputField(
                controller: _contactRelationshipController,
                label: 'Relationship',
              ),
            ),
            const SizedBox(height: 14),
            _scheduleTile(
              icon: Icons.public_rounded,
              iconColor: const Color(0xFFE6A85C),
              title: 'Country',
              value: '$_nextOfKinCountryCode ($_nextOfKinDialCode)',
              onTap: () {
                showCountryPicker(
                  context: context,
                  onSelect: (Country country) {
                    setState(() {
                      _nextOfKinCountryCode = country.countryCode;
                      _nextOfKinDialCode = '+${country.phoneCode}';
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            Theme(
              data: AppTheme.darkTheme,
              child: InputField(
                controller: _contactPhoneController,
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
                controller: _contactEmailController,
                label: 'Email address',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Theme(
              data: AppTheme.darkTheme,
              child: InputField(
                controller: _pinController,
                label: '4-digit PIN',
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This PIN secures sensitive actions in your account.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
