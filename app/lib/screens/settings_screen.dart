import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/theme.dart';
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
      SnackBar(
        content: Text(ok ? 'Settings saved' : 'Could not save, try again'),
        behavior: SnackBarBehavior.floating,
      ),
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
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Check-in frequency',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            _sheetOption(ctx, 'Daily', _frequency == 'Daily'),
            _sheetOption(ctx, 'Weekly', _frequency == 'Weekly'),
            const SizedBox(height: 12),
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

  Widget _sheetOption(BuildContext ctx, String label, bool selected) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppTheme.primary)
          : null,
      onTap: () => Navigator.pop(ctx, label),
    );
  }

  Future<void> _changeGraceWindow() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Grace window',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            for (final int h in <int>[2, 3, 6])
              _sheetOptionInt(ctx, '$h hours', h, _graceHours == h),
            const SizedBox(height: 12),
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

  Widget _sheetOptionInt(
    BuildContext ctx,
    String label,
    int value,
    bool selected,
  ) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppTheme.primary)
          : null,
      onTap: () => Navigator.pop(ctx, value),
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
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Next of kin',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'They receive an alert if you miss a check-in.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 20),
                InputField(controller: name, label: 'Full name'),
                const SizedBox(height: 12),
                InputField(controller: relationship, label: 'Relationship'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Country',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  subtitle: Text(
                    '$selectedCountryCode ($selectedDialCode)',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(Icons.arrow_drop_down, color: Colors.white54),
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
                  label: 'Phone (local number)',
                  hint: 'e.g. 779697569',
                  keyboardType: TextInputType.phone,
                  maxLength: 15,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
                const SizedBox(height: 12),
                InputField(
                  controller: email,
                  label: 'Email (optional)',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save contact'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final String? kinPhoneForApi = PhoneNumberService.toLocalDigitsForApi(
      rawInput: phone.text.trim(),
      isoCode: selectedCountryCode,
    );
    if (kinPhoneForApi == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a valid local number for the selected country.'),
        ),
      );
      return;
    }
    final String? normalizedKinPhone = PhoneNumberService.normalizeLocalToE164(
      rawInput: phone.text.trim(),
      isoCode: selectedCountryCode,
    );
    setState(() {
      _kinName = name.text.trim();
      _kinRelationship = relationship.text.trim();
      _kinCountryCode = selectedCountryCode;
      _kinDialCode = selectedDialCode;
      _kinPhone = PhoneNumberService.toLocalDisplay(normalizedKinPhone ?? '');
      _kinEmail = email.text.trim();
    });
    await _saveProfile(<String, dynamic>{
      'emergency_contact_name': _kinName,
      'emergency_contact_relationship': _kinRelationship,
      'emergency_contact_country_code': _kinCountryCode,
      'emergency_contact_phone': kinPhoneForApi,
      'emergency_contact_email': _kinEmail,
    });
  }

  Future<void> _changePin() async {
    final pin = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Security PIN',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Used to confirm sensitive actions.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            InputField(
              controller: pin,
              label: '4-digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
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
    final user = AuthService.instance.currentUser;
    final String displayName = user?.displayIdentifier ?? 'SafeBangle user';

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Settings'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: <Widget>[
                  _profileHeader(displayName),
                  const SizedBox(height: 24),
                  _sectionTitle('Check-in schedule'),
                  _settingsCard(
                    children: <Widget>[
                      _settingsTile(
                        icon: Icons.schedule_rounded,
                        iconColor: AppTheme.primary,
                        title: 'Call time',
                        value: _displayTime(_checkinTime),
                        onTap: _changeCallTime,
                      ),
                      _divider(),
                      _settingsTile(
                        icon: Icons.repeat_rounded,
                        iconColor: const Color(0xFF5C9CE6),
                        title: 'Frequency',
                        value: _frequency,
                        onTap: _changeFrequency,
                      ),
                      _divider(),
                      _settingsTile(
                        icon: Icons.hourglass_bottom_rounded,
                        iconColor: const Color(0xFFE6A85C),
                        title: 'Grace window',
                        value: '$_graceHours hours after missed call',
                        onTap: _changeGraceWindow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Emergency contact'),
                  _settingsCard(
                    children: <Widget>[
                      _settingsTile(
                        icon: Icons.family_restroom_rounded,
                        iconColor: AppTheme.secondary,
                        title: _kinName.isEmpty ? 'Add next of kin' : _kinName,
                        value: _kinName.isEmpty
                            ? 'Required for missed check-in alerts'
                            : '$_kinRelationship • $_kinDialCode $_kinPhone',
                        onTap: _changeNextOfKin,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Security'),
                  _settingsCard(
                    children: <Widget>[
                      _settingsTile(
                        icon: Icons.lock_rounded,
                        iconColor: const Color(0xFF9B7EDE),
                        title: 'PIN',
                        value: 'Change your 4-digit PIN',
                        onTap: _changePin,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _profileHeader(String name) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppTheme.primary.withValues(alpha: 0.35),
            const Color(0xFF1A1F26),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your safety check-in preferences',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 68,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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

  String _displayTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 18;
    final minute = int.tryParse(parts[1]) ?? 0;
    final tod = TimeOfDay(hour: hour, minute: minute);
    return tod.format(context);
  }
}
