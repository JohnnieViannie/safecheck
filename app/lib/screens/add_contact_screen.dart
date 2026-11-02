import 'dart:async';
import 'dart:convert';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/models/emergency_contact.dart';
import 'package:safecheck/screens/contacts_screen.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/phone_number_service.dart';
import 'package:safecheck/services/storage_service.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({
    super.key,
    this.existingContactCount = 0,
    this.editingContact,
  });

  final int existingContactCount;
  final EmergencyContact? editingContact;

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _fieldBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);

  static const List<String> _relationshipOptions = <String>[
    'Family',
    'Colleague',
    'Friend',
    'Supervisor',
    'Police',
  ];

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;

  String _countryCode = 'UG';
  String _dialCode = '+256';
  String _relationship = 'Family';
  String _priority = 'secondary';
  bool _saving = false;
  bool _sendOptInSms = false;
  String? _error;

  bool get _isEditing => widget.editingContact != null;

  @override
  void initState() {
    super.initState();
    final EmergencyContact? existing = widget.editingContact;
    final List<String> nameParts = existing == null
        ? <String>[]
        : existing.name.trim().split(RegExp(r'\s+'));
    _firstNameController = TextEditingController(
      text: nameParts.isEmpty ? '' : nameParts.first,
    );
    _lastNameController = TextEditingController(
      text: nameParts.length < 2 ? '' : nameParts.sublist(1).join(' '),
    );
    _phoneController = TextEditingController(
      text: existing == null
          ? ''
          : PhoneNumberService.toLocalDisplay(existing.phone),
    );
    if (existing != null) {
      _countryCode = existing.countryCode;
      _dialCode = existing.dialCode;
      _relationship = _relationshipOptions.contains(existing.relationship)
          ? existing.relationship
          : 'Family';
      _priority = existing.role.toLowerCase() == 'primary'
          ? 'primary'
          : 'secondary';
    } else {
      _priority = widget.existingContactCount == 0 ? 'primary' : 'secondary';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<List<EmergencyContact>> _loadExistingContacts() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return <EmergencyContact>[];
    }

    final Map<String, dynamic>? cached =
        await StorageService.instance.getCachedProfile();
    List<EmergencyContact> fromCache = cached == null
        ? <EmergencyContact>[]
        : EmergencyContact.listFromProfile(cached);

    try {
      final response = await ApiService.instance.get(
        '${Endpoints.userProfile}$uid/',
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        await StorageService.instance.saveCachedProfile(data);
        return EmergencyContact.listFromProfile(data);
      }
    } catch (_) {
      // Use cached contacts below.
    }

    if (fromCache.isNotEmpty) {
      return fromCache;
    }

    final profile = AuthService.instance.currentUser;
    if (profile?.emergencyContactsJson != null &&
        profile!.emergencyContactsJson!.trim().isNotEmpty) {
      return EmergencyContact.listFromProfile(<String, dynamic>{
        'emergency_contacts_json': profile.emergencyContactsJson,
      });
    }

    return <EmergencyContact>[];
  }

  Future<void> _saveContact() async {
    final String firstName = _firstNameController.text.trim();
    final String lastName = _lastNameController.text.trim();
    final String fullName = '$firstName $lastName'.trim();
    final String phone = _phoneController.text.trim();

    if (firstName.isEmpty || phone.isEmpty) {
      setState(() => _error = 'First name and phone number are required.');
      return;
    }

    final String? phoneForApi = PhoneNumberService.toLocalDigitsForApi(
      rawInput: phone,
      isoCode: _countryCode,
    );
    if (phoneForApi == null) {
      setState(() => _error = 'Enter a valid phone number for $_countryCode.');
      return;
    }

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'You must be signed in to add a contact.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    List<EmergencyContact> contacts = await _loadExistingContacts();
    final EmergencyContact newContact = EmergencyContact(
      id: widget.editingContact?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: fullName,
      relationship: _relationship,
      countryCode: _countryCode,
      dialCode: _dialCode,
      phone: phoneForApi,
      email: widget.editingContact?.email ?? '',
      role: _priority,
      optInStatus: 'pending',
    );

    if (_isEditing) {
      contacts = contacts
          .map(
            (EmergencyContact contact) =>
                contact.id == newContact.id ? newContact : contact,
          )
          .toList();
    } else {
      if (contacts.length >= ContactsScreen.maxContacts) {
        setState(() {
          _saving = false;
          _error = 'You can add up to ${ContactsScreen.maxContacts} contacts.';
        });
        return;
      }
      contacts = <EmergencyContact>[...contacts, newContact];
    }

    if (_priority == 'primary') {
      contacts = contacts
          .map(
            (EmergencyContact contact) => contact.id == newContact.id
                ? contact.copyWith(role: 'primary', optInStatus: newContact.optInStatus)
                : contact.copyWith(role: 'secondary'),
          )
          .toList();
    } else if (!_isEditing) {
      contacts[contacts.length - 1] =
          newContact.copyWith(role: 'secondary', optInStatus: 'pending');
    }

    final bool saved = await _persistContacts(contacts);

    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error = AuthService.instance.lastProfileSaveError ??
            'Could not save contact. Try again.';
      });
      return;
    }

    final String contactId = newContact.id;
    final bool sendOptIn = !_isEditing && _sendOptInSms;

    if (!mounted) return;
    Navigator.of(context).pop(true);

    if (sendOptIn) {
      unawaited(_sendOptInSmsInBackground(uid: uid, contactId: contactId));
    }
  }

  Future<void> _sendOptInSmsInBackground({
    required String uid,
    required String contactId,
  }) async {
    try {
      await ApiService.instance.post(
        Endpoints.sendContactOptIn,
        body: <String, dynamic>{
          'uid': uid,
          'contact_id': contactId,
        },
      );
    } catch (_) {
      // Contact is already saved; opt-in can be retried later.
    }
  }

  Future<bool> _persistContacts(List<EmergencyContact> contacts) async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return false;
    }

    final EmergencyContact primaryContact = contacts.isEmpty
        ? EmergencyContact(
            id: 'primary',
            name: '',
            relationship: '',
            countryCode: 'UG',
            dialCode: '+256',
            phone: '',
          )
        : contacts.firstWhere(
            (EmergencyContact contact) =>
                contact.role.toLowerCase() == 'primary',
            orElse: () => contacts.first,
          );

    final List<Map<String, dynamic>> payload =
        contacts.map((EmergencyContact contact) => contact.toMap()).toList();

    final String? primaryPhoneForApi = PhoneNumberService.toLocalDigitsForApi(
      rawInput: primaryContact.phone,
      isoCode: primaryContact.countryCode,
    );

    return AuthService.instance.createOrUpdateUser(
      uid: uid,
      phoneNumber: AuthService.instance.currentUser?.phoneNumber ?? '',
      extra: <String, dynamic>{
        'emergency_contacts_json': jsonEncode(payload),
        if (contacts.isNotEmpty &&
            primaryContact.name.trim().isNotEmpty &&
            primaryPhoneForApi != null)
          ...<String, dynamic>{
            'emergency_contact_name': primaryContact.name.trim(),
            'emergency_contact_relationship': primaryContact.relationship.trim(),
            'emergency_contact_country_code': primaryContact.countryCode,
            'emergency_contact_phone': primaryPhoneForApi,
            'emergency_contact_email': primaryContact.email.trim(),
          },
      },
    );
  }

  Future<void> _deleteContact() async {
    if (!_isEditing || widget.editingContact == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: _fieldBackground,
        title: const Text('Remove contact?', style: TextStyle(color: Colors.white)),
        content: Text(
          '${widget.editingContact!.name} will no longer receive alerts.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final List<EmergencyContact> loaded = await _loadExistingContacts();

    List<EmergencyContact> contacts = loaded
        .where(
          (EmergencyContact contact) =>
              contact.id != widget.editingContact!.id,
        )
        .toList();

    if (contacts.isNotEmpty &&
        !contacts.any(
          (EmergencyContact contact) =>
              contact.role.toLowerCase() == 'primary',
        )) {
      contacts[0] = contacts.first.copyWith(role: 'primary');
    }

    final bool saved = await _persistContacts(contacts);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error = AuthService.instance.lastProfileSaveError ??
            'Could not remove contact. Try again.';
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      onSelect: (Country country) {
        setState(() {
          _countryCode = country.countryCode;
          _dialCode = '+${country.phoneCode}';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildBackRow(),
                    const SizedBox(height: 20),
                    Text(
                      _isEditing ? 'Edit contact' : 'Add contact',
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Georgia',
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This person will receive an SMS if you miss a check-in.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _buildField(
                            label: 'FIRST NAME',
                            controller: _firstNameController,
                            hint: 'First name',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            label: 'LAST NAME',
                            controller: _lastNameController,
                            hint: 'Last name',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildSectionLabel('PHONE NUMBER'),
                    const SizedBox(height: 10),
                    _buildPhoneRow(),
                    const SizedBox(height: 24),
                    _buildSectionLabel('RELATIONSHIP'),
                    const SizedBox(height: 12),
                    _buildRelationshipChips(),
                    const SizedBox(height: 24),
                    _buildSectionLabel('ALERT PRIORITY'),
                    const SizedBox(height: 12),
                    _buildPriorityOption(
                      title: 'Primary — alert first',
                      selected: _priority == 'primary',
                      onTap: () => setState(() => _priority = 'primary'),
                    ),
                    const SizedBox(height: 10),
                    _buildPriorityOption(
                      title: 'Secondary — backup',
                      selected: _priority == 'secondary',
                      onTap: () => setState(() => _priority = 'secondary'),
                    ),
                    if (!_isEditing) ...<Widget>[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _fieldBackground.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Send opt-in SMS after saving (optional)',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                            ),
                            Switch.adaptive(
                              value: _sendOptInSms,
                              activeTrackColor: _accent.withValues(alpha: 0.45),
                              activeThumbColor: _accent,
                              onChanged: (bool value) =>
                                  setState(() => _sendOptInSms = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFF87171),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: <Widget>[
                  if (_isEditing) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _saving ? null : _deleteContact,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF87171),
                          side: BorderSide(
                            color: const Color(0xFFF87171).withValues(alpha: 0.45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Remove contact',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveContact,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF0A192F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _saving
                            ? 'Saving...'
                            : _isEditing
                                ? 'Save contact'
                                : _sendOptInSms
                                    ? 'Save & send opt-in SMS'
                                    : 'Save contact',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackRow() {
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.arrow_back_rounded, color: _accent, size: 20),
            const SizedBox(width: 6),
            Text(
              'Contacts',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _accent.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: _accent.withValues(alpha: 0.82),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSectionLabel(label),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
            filled: true,
            fillColor: _fieldBackground,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _accent.withValues(alpha: 0.55)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneRow() {
    return Row(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: _fieldBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                '$_countryCode $_dialCode',
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: '780 000 000',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
              filled: true,
              fillColor: _fieldBackground,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _accent.withValues(alpha: 0.55)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRelationshipChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _relationshipOptions.map((String option) {
        final bool selected = _relationship == option;
        return GestureDetector(
          onTap: () => setState(() => _relationship = option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? _accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? _accent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Text(
              option,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? _accent
                    : Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriorityOption({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: _fieldBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected ? _accent : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
