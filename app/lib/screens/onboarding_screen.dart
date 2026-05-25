import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/widgets/custom_button.dart';
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
  }

  void _previousStep() {
    if (_step == 0) {
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  Future<void> _completeOnboarding() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Session expired. Please login again.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    if (!_validateCurrentStep()) {
      setState(() => _saving = false);
      return;
    }

    try {
      final Duration checkInPeriod = _frequencyToDuration(_frequency);
      final Duration gracePeriod = Duration(hours: _graceHours);
      final DateTime now = DateTime.now();
      final String normalizedNextOfKinPhone =
          PhoneNumberService.normalizeLocalToE164(
            rawInput: _contactPhoneController.text.trim(),
            isoCode: _nextOfKinCountryCode,
          )!;
      final String checkinTimeText =
          '${_checkinTime.hour.toString().padLeft(2, '0')}:${_checkinTime.minute.toString().padLeft(2, '0')}';
      await StorageService.instance.savePeriodDurations(
        checkInPeriod: checkInPeriod,
        gracePeriod: gracePeriod,
      );
      await StorageService.instance.saveSchedule(
        checkinTime: checkinTimeText,
        checkinFrequency: _frequency,
      );
      await AlarmScheduler.instance.ensureAlarmsScheduled();
      await StorageService.instance.saveLastCheckIn(now);
      await AuthService.instance.createOrUpdateUser(
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
          'timezone': DateTime.now().timeZoneName,
          'emergency_contact_name': _contactNameController.text.trim(),
          'emergency_contact_relationship': _contactRelationshipController.text
              .trim(),
          'emergency_contact_country_code': _nextOfKinCountryCode,
          'emergency_contact_phone': normalizedNextOfKinPhone,
          'emergency_contact_email': _contactEmailController.text.trim(),
          'pin': _pinController.text.trim(),
          'last_check_in_at': now.toIso8601String(),
          'max_retry_attempts': 3,
        },
      );
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
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
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
    return ChoiceChip(
      label: Text('${hours}h'),
      selected: selected,
      onSelected: (_) => setState(() => _graceHours = hours),
    );
  }

  Future<void> _pickCheckinTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkinTime,
    );
    if (picked != null) {
      setState(() => _checkinTime = picked);
    }
  }

  @override
  void dispose() {
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
    final double progress = (_step + 1) / 4;
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Setup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            children: <Widget>[
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step ${_step + 1} of 4',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ListView(
                    children: <Widget>[
                      Text(
                        _titleForStep(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitleForStep(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      _buildStepBody(),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _previousStep,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: CustomButton(
                      label: _step == 3 ? 'Finish Setup' : 'Continue',
                      loading: _saving,
                      onPressed: _step == 3 ? _completeOnboarding : _nextStep,
                    ),
                  ),
                ],
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
        return 'Choose how and when SafeBangle should call you.';
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
            InputField(
              controller: _fullNameController,
              label: 'Your full name',
            ),
            const SizedBox(height: 14),
            const Text(
              'Profile type',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userTypes
                  .map(
                    (String type) => ChoiceChip(
                      label: Text(type),
                      selected: _selectedUserType == type,
                      onSelected: (_) =>
                          setState(() => _selectedUserType = type),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      case 1:
        return Column(
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily check-in'),
              subtitle: const Text('Turn off for weekly check-in instead'),
              trailing: Switch(
                value: _frequency == 'Daily',
                onChanged: (bool value) =>
                    setState(() => _frequency = value ? 'Daily' : 'Weekly'),
              ),
            ),
            const Divider(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Scheduled call time'),
              subtitle: Text(_checkinTime.format(context)),
              trailing: TextButton(
                onPressed: _pickCheckinTime,
                child: const Text('Change'),
              ),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Retry grace window',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: <Widget>[_graceChip(2), _graceChip(3), _graceChip(6)],
            ),
          ],
        );
      case 2:
        return Column(
          children: <Widget>[
            InputField(
              controller: _contactNameController,
              label: 'Next of kin name',
            ),
            const SizedBox(height: 12),
            InputField(
              controller: _contactRelationshipController,
              label: 'Relationship',
            ),
            const SizedBox(height: 12),
            InputField(
              controller: _contactPhoneController,
              label: 'Next of kin phone (local, no + code)',
              hint: 'Enter local number',
              keyboardType: TextInputType.phone,
              maxLength: 15,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Country'),
              subtitle: Text('$_nextOfKinCountryCode ($_nextOfKinDialCode)'),
              trailing: const Icon(Icons.arrow_drop_down),
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
            const SizedBox(height: 12),
            InputField(
              controller: _contactEmailController,
              label: 'Next of kin email',
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        );
      case 3:
        return Column(
          children: <Widget>[
            InputField(
              controller: _pinController,
              label: '4-digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
            ),
            const SizedBox(height: 10),
            const Text(
              'This PIN helps secure sensitive actions in your account.',
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
