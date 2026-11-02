import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safecheck/models/vault_document.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/offline_sync_service.dart';

class DocumentVaultService {
  DocumentVaultService._();

  static final DocumentVaultService instance = DocumentVaultService._();

  static const String _storageKey = 'document_vault_items';

  Future<List<VaultDocument>> loadDocuments() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        final response = await ApiService.instance.get(
          Endpoints.vaultDocuments,
          query: <String, dynamic>{'uid': uid},
        );
        if (response.statusCode == 200) {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is List) {
            final List<VaultDocument> remote = decoded
                .whereType<Map<String, dynamic>>()
                .map(_vaultDocumentFromApi)
                .where(
                  (VaultDocument doc) =>
                      doc.id.isNotEmpty && !doc.isEmpty,
                )
                .toList();
            await _cacheDocuments(remote);
            return remote;
          }
        }
      } catch (_) {
        // Fall back to last server cache below.
      }
      return await _loadCachedDocuments();
    }

    return await _loadCachedDocuments();
  }

  Future<List<VaultDocument>> _loadCachedDocuments() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <VaultDocument>[];
    }
    return VaultDocument.listFromJson(raw);
  }

  Future<void> _cacheDocuments(List<VaultDocument> documents) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, VaultDocument.listToJson(documents));
  }

  Future<VaultDocument?> uploadDocument({
    required List<VaultDocument> current,
    String? slotId,
    String? defaultTitle,
  }) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[
          'pdf',
          'doc',
          'docx',
          'txt',
          'jpg',
          'jpeg',
          'png',
        ],
        withData: false,
      );
    } on Exception catch (error) {
      throw DocumentVaultUploadException(
        error.toString().contains('MissingPluginException')
            ? 'File picker is not ready. Stop the app completely, then run '
                'flutter run again (hot reload is not enough after adding file_picker).'
            : 'Could not open file picker. Try again.',
      );
    }
    if (result == null || result.files.isEmpty) {
      return null;
    }

    final PlatformFile picked = result.files.first;
    if (picked.path == null || picked.path!.isEmpty) {
      return null;
    }

    final File source = File(picked.path!);
    if (!await source.exists()) {
      return null;
    }

    final String title = defaultTitle?.trim().isNotEmpty == true
        ? defaultTitle!.trim()
        : _basenameWithoutExtension(picked.name);
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw DocumentVaultUploadException('Sign in required to upload documents.');
    }

    try {
      final http.MultipartFile file = await http.MultipartFile.fromPath(
        'file',
        source.path,
        filename: picked.name,
      );
      final response = await ApiService.instance.postMultipart(
        Endpoints.vaultUpload,
        fields: <String, String>{
          'uid': uid,
          'title': title,
          if (slotId != null) 'slot_id': slotId,
        },
        file: file,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        return _vaultDocumentFromApi(data);
      }
    } catch (error) {
      if (!OfflineSyncService.isNetworkError(error)) {
        throw DocumentVaultUploadException('Upload failed. Try again.');
      }
    }

    final Directory vaultDir = await _vaultDirectory();
    final String extension = _fileExtension(picked.name);
    final String safeId =
        slotId ?? 'doc_${DateTime.now().millisecondsSinceEpoch}';
    final String storedName =
        '$safeId${extension.isEmpty ? '' : '.$extension'}';
    final File destination = File('${vaultDir.path}/$storedName');
    await destination.writeAsBytes(await source.readAsBytes(), flush: true);

    await OfflineSyncService.instance.enqueue(
      type: OfflineSyncService.opVaultUpload,
      payload: <String, dynamic>{
        'uid': uid,
        'title': title,
        if (slotId != null) 'slot_id': slotId,
        'local_path': destination.path,
        'filename': picked.name,
      },
    );

    final int sizeBytes = picked.size > 0
        ? picked.size
        : await destination.length();

    return VaultDocument(
      id: safeId,
      title: title,
      iconKey: _iconKeyForTitle(title),
      updatedAt: DateTime.now(),
      format: extension.isEmpty ? 'FILE' : extension.toUpperCase(),
      sizeBytes: sizeBytes,
      status: VaultDocumentStatus.active,
      localPath: destination.path,
    );
  }

  Future<bool> deleteDocument(String docId) async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return false;
    }
    try {
      http.Response response = await ApiService.instance.post(
        Endpoints.vaultDelete(docId),
        body: <String, dynamic>{'uid': uid},
      );
      if (response.statusCode == 405) {
        response = await ApiService.instance.delete(
          Endpoints.vaultDocument(docId),
          query: <String, dynamic>{'uid': uid},
          body: <String, dynamic>{'uid': uid},
        );
      }
      return response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404;
    } catch (error) {
      return OfflineSyncService.isNetworkError(error);
    }
  }

  Future<List<VaultDocument>> removeDocument({
    required String docId,
    required List<VaultDocument> current,
  }) async {
    VaultDocument? target;
    for (final VaultDocument doc in current) {
      if (doc.id == docId) {
        target = doc;
        break;
      }
    }

    await deleteDocument(docId);

    await OfflineSyncService.instance.cancelVaultUpload(
      docId: docId,
      localPath: target?.localPath,
    );

    if (target?.localPath != null && target!.localPath!.isNotEmpty) {
      final File file = File(target.localPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final List<VaultDocument> next =
        current.where((VaultDocument doc) => doc.id != docId).toList();
    await _cacheDocuments(next);
    return next;
  }

  Future<List<VaultDocument>> applyUpload({
    required List<VaultDocument> current,
    required VaultDocument uploaded,
    String? slotId,
  }) async {
    final List<VaultDocument> next = List<VaultDocument>.from(current);
    final int slotIndex = slotId == null
        ? -1
        : next.indexWhere((VaultDocument doc) => doc.id == slotId);

    if (slotIndex >= 0) {
      next[slotIndex] = uploaded.copyWith(id: next[slotIndex].id);
    } else {
      final int existingIndex =
          next.indexWhere((VaultDocument doc) => doc.id == uploaded.id);
      if (existingIndex >= 0) {
        next[existingIndex] = uploaded;
      } else {
        next.add(uploaded);
      }
    }

    await _cacheDocuments(next);
    return next;
  }

  VaultDocument _vaultDocumentFromApi(Map<String, dynamic> map) {
    return VaultDocument(
      id: map['doc_id'] as String? ?? map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Document',
      iconKey: _iconKeyForTitle(map['title'] as String? ?? ''),
      updatedAt: map['uploaded_at'] == null
          ? DateTime.now()
          : DateTime.tryParse(map['uploaded_at'] as String) ?? DateTime.now(),
      format: map['format'] as String?,
      sizeBytes: map['size_bytes'] as int?,
      status: (map['status'] as String?) == 'empty'
          ? VaultDocumentStatus.empty
          : VaultDocumentStatus.active,
    );
  }

  String _iconKeyForTitle(String title) {
    final String lower = title.toLowerCase();
    if (lower.contains('medical') || lower.contains('health')) {
      return 'medical';
    }
    if (lower.contains('kin') || lower.contains('contact')) {
      return 'contacts';
    }
    return 'document';
  }

  Future<Directory> _vaultDirectory() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory vaultDir = Directory('${appDir.path}/document_vault');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  String _fileExtension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1);
  }

  String _basenameWithoutExtension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }
}

class DocumentVaultUploadException implements Exception {
  DocumentVaultUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
