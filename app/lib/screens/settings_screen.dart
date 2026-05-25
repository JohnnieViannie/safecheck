import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/widgets/input_field.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String _checkinTime = '18:00';
  String _frequency = 'Daily';
  int _graceHours = 2;
  String _kinName = '';
  String _kinPhone = '';
  String _kinCountryCode = 'UG';
  String _kinDialCode = '+256';
  String _kinEmail = '';
  String _kinRelationship = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = AuthService.instance.currentUser;
    if (user != null) {
      final profile = await AuthService.instance.getUserProfile(user.uid);
      if (!mounted) return;
      if (profile != null) {
        _checkinTime = profile.checkinTime ?? _checkinTime;
        _frequency = profile.checkinFrequency ?? _frequency;
        _graceHours = profile.gracePeriodHours ?? _graceHours;
        _kinName = profile.emergencyContactName ?? '';
        _kinPhone = PhoneNumberService.toLocalDisplay(
          profile.emergencyContactPhone ?? '',
        );
        _kinCountryCode = profile.emergencyContactCountryCode ?? 'UG';
        _kinEmail = profile.emergencyContactEmail ?? '';
        _kinRelationship = profile.emergencyContactRelationship ?? '';
      }
    }
    setState(() => _loading = false);
  }

  Future<String> _deviceTimezone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> _saveProfile(Map<String, dynamic> extra) async {
    extra['timezone'] = await _deviceTimezone();
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Log in again.')),
      );
      return;
    }

    final ok = await AuthService.instance.createOrUpdateUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber ?? '',
      extra: extra,
    );
    if (ok) {
      await SafetyService.instance.logTimelineEvent(
        uid: user.uid,
        eventType: 'settings_updated',
        status: 'success',
        payload: <String, dynamic>{'fields': extra.keys.toList()},
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Saved' : 'Could not save, try again')),
    );
  }

  Future<void> _changeCallTime() async {
    final parts = _checkinTime.split(':');
    final now = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => _checkinTime = time);
    await StorageService.instance.saveSchedule(
      checkinTime: _checkinTime,
      checkinFrequency: _frequency,
    );
    await _saveProfile(<String, dynamic>{'checkin_time': _checkinTime});
  }

  Future<void> _changeFrequency() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('Daily'),
              onTap: () => Navigator.pop(ctx, 'Daily'),
            ),
            ListTile(
              title: const Text('Weekly'),
              onTap: () => Navigator.pop(ctx, 'Weekly'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _frequency = selected);
    await StorageService.instance.saveSchedule(
      checkinTime: _checkinTime,
      checkinFrequency: _frequency,
    );
    await _saveProfile(<String, dynamic>{'checkin_frequency': _frequency});
  }

  Future<void> _changeGraceWindow() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final h in <int>[2, 3, 6])
              ListTile(
                title: Text('$h hours'),
                onTap: () => Navigator.pop(ctx, h),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _graceHours = selected);
    await _saveProfile(<String, dynamic>{'grace_period_hours': _graceHours});
    await StorageService.instance.savePeriodDurations(
      checkInPeriod: _frequency == 'Weekly'
          ? const Duration(days: 7)
          : const Duration(days: 1),
      gracePeriod: Duration(hours: _graceHours),
    );
  }

  Future<void> _changeNextOfKin() async {
    final name = TextEditingController(text: _kinName);
    final relationship = TextEditingController(text: _kinRelationship);
    final phone = TextEditingController(text: _kinPhone);
    final email = TextEditingController(text: _kinEmail);
    String selectedCountryCode = _kinCountryCode;
    String selectedDialCode = _kinDialCode;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                InputField(controller: name, label: 'Name'),
                const SizedBox(height: 10),
                InputField(controller: relationship, label: 'Relationship'),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Country'),
                  subtitle: Text('$selectedCountryCode ($selectedDialCode)'),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: () {
                    showCountryPicker(
                      context: ctx,
                      onSelect: (Country country) {
                        setModalState(() {
                          selectedCountryCode = country.countryCode;
                          selectedDialCode = '+${country.phoneCode}';
                        });
                      },
                    );
                  },
                ),
                InputField(
                  controller: phone,
                  label: 'Phone (local, no + code)',
                  hint: 'Enter local number',
                  keyboardType: TextInputType.phone,
                  maxLength: 15,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
                const SizedBox(height: 10),
                InputField(
                  controller: email,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final String? normalizedKinPhone = PhoneNumberService.normalizeLocalToE164(
      rawInput: phone.text.trim(),
      isoCode: selectedCountryCode,
    );
    if (normalizedKinPhone == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a valid local number for the selected country.'),
        ),
      );
      return;
    }
    setState(() {
      _kinName = name.text.trim();
      _kinRelationship = relationship.text.trim();
      _kinCountryCode = selectedCountryCode;
      _kinDialCode = selectedDialCode;
      _kinPhone = PhoneNumberService.toLocalDisplay(normalizedKinPhone);
      _kinEmail = email.text.trim();
    });
    await _saveProfile(<String, dynamic>{
      'emergency_contact_name': _kinName,
      'emergency_contact_relationship': _kinRelationship,
      'emergency_contact_country_code': _kinCountryCode,
      'emergency_contact_phone': normalizedKinPhone,
      'emergency_contact_email': _kinEmail,
    });
  }

  Future<void> _changePin() async {
    final pin = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InputField(
              controller: pin,
              label: '4-digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save PIN'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || pin.text.trim().length != 4) return;
    await _saveProfile(<String, dynamic>{'pin': pin.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Safety',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            _settingsItem(
              icon: Icons.schedule,
              title: 'Call time',
              subtitle: _displayTime(_checkinTime),
              onTap: _changeCallTime,
            ),
            _settingsItem(
              icon: Icons.repeat,
              title: 'Check-in frequency',
              subtitle: _frequency,
              onTap: _changeFrequency,
            ),
            _settingsItem(
              icon: Icons.timer,
              title: 'Grace window',
              subtitle: '$_graceHours hours',
              onTap: _changeGraceWindow,
            ),
            _settingsItem(
              icon: Icons.contacts,
              title: 'Next of kin',
              subtitle: _kinName.isEmpty
                  ? 'Add details'
                  : '$_kinName • $_kinPhone',
              onTap: _changeNextOfKin,
            ),
            _settingsItem(
              icon: Icons.lock,
              title: 'Security PIN',
              subtitle: 'Change PIN',
              onTap: _changePin,
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(radius: 18, child: Icon(icon, size: 18)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  String _displayTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 18;
    final minute = int.tryParse(parts[1]) ?? 0;
    final tod = TimeOfDay(hour: hour, minute: minute);
    return tod.format(context);
  }
}
