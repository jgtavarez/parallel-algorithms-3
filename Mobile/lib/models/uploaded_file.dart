class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.filename,
    required this.originalName,
    required this.contentType,
    required this.size,
    required this.url,
    required this.createdAt,
  });

  final int id;
  final String filename;
  final String originalName;
  final String contentType;
  final int size;
  final String url;
  final DateTime createdAt;

  bool get isImage => contentType.startsWith('image/');

  factory UploadedFile.fromJson(Map<String, dynamic> json) => UploadedFile(
    id: json['id'],
    filename: json['filename'],
    originalName: json['originalName'],
    contentType: json['contentType'],
    size: json['size'],
    url: json['url'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}
