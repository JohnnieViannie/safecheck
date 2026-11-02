import 'dart:convert';

enum VaultDocumentStatus { active, empty }

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.title,
    required this.iconKey,
    this.updatedAt,
    this.format,
    this.sizeBytes,
    this.status = VaultDocumentStatus.active,
    this.localPath,
  });

  final String id;
  final String title;
  final String iconKey;
  final DateTime? updatedAt;
  final String? format;
  final int? sizeBytes;
  final VaultDocumentStatus status;
  final String? localPath;

  bool get isEmpty => status == VaultDocumentStatus.empty;

  String get sizeLabel {
    if (sizeBytes == null || sizeBytes! <= 0) {
      return '';
    }
    if (sizeBytes! < 1024) {
      return '${sizeBytes!}B';
    }
    return '${(sizeBytes! / 1024).round()}KB';
  }

  String get updatedLabel {
    if (updatedAt == null) {
      return '';
    }
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final DateTime date = updatedAt!.toLocal();
    return 'Updated ${months[date.month - 1]} ${date.day}';
  }

  String get subtitle {
    if (isEmpty) {
      return 'Tap to upload';
    }
    final List<String> parts = <String>[
      if (updatedLabel.isNotEmpty) updatedLabel,
      if (format != null && format!.isNotEmpty) format!,
      if (sizeLabel.isNotEmpty) sizeLabel,
    ];
    return parts.join(' · ');
  }

  VaultDocument copyWith({
    String? id,
    String? title,
    String? iconKey,
    DateTime? updatedAt,
    String? format,
    int? sizeBytes,
    VaultDocumentStatus? status,
    String? localPath,
  }) {
    return VaultDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      iconKey: iconKey ?? this.iconKey,
      updatedAt: updatedAt ?? this.updatedAt,
      format: format ?? this.format,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'iconKey': iconKey,
      'updatedAt': updatedAt?.toIso8601String(),
      'format': format,
      'sizeBytes': sizeBytes,
      'status': status.name,
      'localPath': localPath,
    };
  }

  factory VaultDocument.fromMap(Map<String, dynamic> map) {
    return VaultDocument(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Document',
      iconKey: map['iconKey'] as String? ?? 'document',
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.tryParse(map['updatedAt'] as String),
      format: map['format'] as String?,
      sizeBytes: map['sizeBytes'] as int?,
      status: VaultDocumentStatus.values.firstWhere(
        (VaultDocumentStatus value) => value.name == map['status'],
        orElse: () => VaultDocumentStatus.active,
      ),
      localPath: map['localPath'] as String?,
    );
  }

  static List<VaultDocument> listFromJson(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <VaultDocument>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(VaultDocument.fromMap)
        .toList();
  }

  static String listToJson(List<VaultDocument> documents) {
    return jsonEncode(documents.map((VaultDocument doc) => doc.toMap()).toList());
  }
}
