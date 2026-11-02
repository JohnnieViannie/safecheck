import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safecheck/screens/add_contact_screen.dart';
import 'package:safecheck/models/emergency_contact.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/storage_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  static const int maxContacts = 5;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);

  List<EmergencyContact> _contacts = <EmergencyContact>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _contacts = <EmergencyContact>[];
        _loading = false;
      });
      return;
    }

    final Map<String, dynamic>? cached =
        await StorageService.instance.getCachedProfile();
    if (cached != null && mounted) {
      setState(() {
        _contacts = EmergencyContact.listFromProfile(cached);
        _loading = false;
      });
    }

    try {
      final response = await ApiService.instance.get(
        '${Endpoints.userProfile}$uid/',
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        await StorageService.instance.saveCachedProfile(data);
        if (!mounted) return;
        setState(() {
          _contacts = EmergencyContact.listFromProfile(data);
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // Fall back to cached profile fields below.
    }

    final profile = await AuthService.instance.getUserProfile(uid);
    if (!mounted) return;
    setState(() {
      _contacts = profile == null
          ? <EmergencyContact>[]
          : EmergencyContact.listFromProfile(<String, dynamic>{
              'emergency_contacts_json': profile.emergencyContactsJson,
              'emergency_contact_name': profile.emergencyContactName,
              'emergency_contact_relationship':
                  profile.emergencyContactRelationship,
              'emergency_contact_country_code':
                  profile.emergencyContactCountryCode,
              'emergency_contact_phone': profile.emergencyContactPhone,
              'emergency_contact_email': profile.emergencyContactEmail,
            });
      _loading = false;
    });
  }

  Future<void> _openAddContact({EmergencyContact? editing}) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddContactScreen(
          existingContactCount: _contacts.length,
          editingContact: editing,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      if (AuthService.instance.lastSaveQueuedOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Contact saved on this phone — will sync to the server when online.',
            ),
          ),
        );
      } else if (await OfflineSyncService.instance.hasPending()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Some changes are still waiting to sync to the server.',
            ),
          ),
        );
      }
    }
  }

  Color _avatarColor(int index) {
    return index.isEven ? _accent : const Color(0xFF1D4ED8);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              color: _accent,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildHeader(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('PRIMARY CONTACTS'),
                          const SizedBox(height: 14),
                          if (_contacts.isEmpty)
                            _buildEmptyState()
                          else
                            ...List<Widget>.generate(_contacts.length, (int index) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == _contacts.length - 1 ? 0 : 12,
                                ),
                                child: _buildContactCard(
                                  _contacts[index],
                                  index: index,
                                ),
                              );
                            }),
                          if (_contacts.length < ContactsScreen.maxContacts) ...<Widget>[
                            const SizedBox(height: 14),
                            _buildAddContactButton(),
                          ],
                          const SizedBox(height: 24),
                          _buildPrivacyNote(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        const Text(
          'Contacts',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            fontFamily: 'Georgia',
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Material(
          color: _accent.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () => _openAddContact(),
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.add_rounded, color: _accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: _accent.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'No emergency contacts yet.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add someone who should be alerted if you miss a check-in.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _openAddContact(),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF0A192F),
            ),
            child: const Text('Add contact'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(EmergencyContact contact, {required int index}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAddContact(editing: contact),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _avatarColor(index).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  contact.initials,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _avatarColor(index),
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
                      contact.subtitleLine,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _badge(
                          contact.roleLabel,
                          color: _accent,
                          filled: true,
                        ),
                        _badge(
                          contact.optInLabel,
                          color: contact.isOptedIn
                              ? _accent
                              : Colors.white.withValues(alpha: 0.55),
                          filled: contact.isOptedIn,
                        ),
                      ],
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

  Widget _badge(
    String label, {
    required Color color,
    required bool filled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: filled ? 0.35 : 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Widget _buildAddContactButton() {
    final int nextCount = _contacts.length + 1;
    final String label = switch (nextCount) {
      2 => 'Add second contact',
      3 => 'Add third contact',
      4 => 'Add fourth contact',
      5 => 'Add fifth contact',
      _ => 'Add contact',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAddContact(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accent.withValues(alpha: 0.45),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: _accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Up to ${ContactsScreen.maxContacts} contacts',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
              'Contacts receive an SMS only when an alert fires. They are never tracked or monitored. All contacts can opt out by replying STOP.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.52),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
