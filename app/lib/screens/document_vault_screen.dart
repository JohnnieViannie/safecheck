import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safecheck/models/vault_document.dart';
import 'package:safecheck/services/document_vault_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';

class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _activeGreen = Color(0xFF22C55E);

  List<VaultDocument> _documents = <VaultDocument>[];
  bool _loading = true;
  bool _uploading = false;
  String? _deletingDocId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<VaultDocument> documents =
        await DocumentVaultService.instance.loadDocuments();
    if (!mounted) return;
    setState(() {
      _documents = documents
          .where(
            (VaultDocument doc) => doc.id.isNotEmpty && !doc.isEmpty,
          )
          .toList();
      _loading = false;
    });
  }

  Future<void> _upload({String? slotId, String? defaultTitle}) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final VaultDocument? uploaded =
          await DocumentVaultService.instance.uploadDocument(
        current: _documents,
        slotId: slotId,
        defaultTitle: defaultTitle,
      );
      if (uploaded == null) {
        return;
      }
      final List<VaultDocument> next =
          await DocumentVaultService.instance.applyUpload(
        current: _documents,
        uploaded: uploaded,
        slotId: slotId,
      );
      if (!mounted) return;
      setState(() {
        _documents = next
            .where(
              (VaultDocument doc) => doc.id.isNotEmpty && !doc.isEmpty,
            )
            .toList();
      });

      final List<VaultDocument> refreshed =
          await DocumentVaultService.instance.loadDocuments();
      if (!mounted) return;
      if (refreshed.isNotEmpty) {
        setState(() {
          _documents = refreshed
              .where(
                (VaultDocument doc) => doc.id.isNotEmpty && !doc.isEmpty,
              )
              .toList();
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${uploaded.title}" added to your vault.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      final bool pendingSync = await OfflineSyncService.instance.hasPending();
      if (pendingSync && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload queued — will sync when back online.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on DocumentVaultUploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _deleteDocument(VaultDocument document) async {
    if (_deletingDocId != null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: _cardBackground,
        title: const Text('Delete document?', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${document.title}" will be removed from your vault.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingDocId = document.id);
    try {
      final List<VaultDocument> next =
          await DocumentVaultService.instance.removeDocument(
        docId: document.id,
        current: _documents,
      );
      if (!mounted) return;
      setState(() => _documents = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${document.title}" deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete document. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingDocId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : Column(
                children: <Widget>[
                  Expanded(
                    child: RefreshIndicator(
                      color: _accent,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        children: <Widget>[
                        _buildTopRow(),
                        const SizedBox(height: 20),
                        const Text(
                          'Document Vault',
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Georgia',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Documents released to contacts only when an alert fires. SafeCheck never reads these files.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Colors.white.withValues(alpha: 0.52),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildEncryptionCard(),
                        const SizedBox(height: 28),
                        _buildSectionLabel('YOUR DOCUMENTS'),
                        const SizedBox(height: 12),
                        if (_documents.isEmpty)
                          _buildEmptyVault()
                        else
                          for (final VaultDocument document in _documents) ...<Widget>[
                            _buildDocumentCard(document),
                            const SizedBox(height: 12),
                          ],
                      ],
                    ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _uploading ? null : () => _upload(),
                        icon: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _accent,
                                ),
                              )
                            : const Icon(Icons.add_rounded, color: _accent),
                        label: Text(
                          _uploading ? 'Uploading…' : 'Upload new document',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _accent.withValues(alpha: 0.55)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      children: <Widget>[
        InkWell(
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
                  'Back',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _accent.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: _accent.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              Text(
                'ENCRYPTED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: _accent.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEncryptionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFC9A86C).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Color(0xFFC9A86C),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                children: const <TextSpan>[
                  TextSpan(
                    text: 'AES-256 encrypted',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' on your device. Only your emergency contacts receive these when you miss a check-in.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVault() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        'No documents yet. Upload files here — they are stored on your SafeCheck account and released to contacts only when an alert fires.',
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Colors.white.withValues(alpha: 0.58),
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
        letterSpacing: 1.3,
        color: _accent.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildDocumentCard(VaultDocument document) {
    final bool isDeleting = _deletingDocId == document.id;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: <Widget>[
            _buildDocumentIcon(document),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    document.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    document.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.48),
                    ),
                  ),
                ],
              ),
            ),
            _activeBadge(),
            const SizedBox(width: 8),
            IconButton(
              onPressed: isDeleting ? null : () => _deleteDocument(document),
              icon: isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFF87171),
                      ),
                    )
                  : Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentIcon(VaultDocument document) {
    final IconData icon = switch (document.iconKey) {
      'contacts' => Icons.person_outline_rounded,
      'medical' => Icons.medical_services_outlined,
      _ => Icons.description_outlined,
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _accent, size: 22),
    );
  }

  Widget _activeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _activeGreen.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _activeGreen.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'ACTIVE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: _activeGreen,
        ),
      ),
    );
  }
}
