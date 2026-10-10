import 'dart:io';

const _definedApiUrl = String.fromEnvironment('API_URL');

// The Android emulator reaches the host machine through 10.0.2.2.
final String apiUrl = _definedApiUrl.isNotEmpty
    ? _definedApiUrl
    : Platform.isAndroid
    ? 'http://10.0.2.2:3000'
    : 'http://localhost:3000';

// Local uploads are relative paths; on GCP they are full Cloud Storage URLs.
String fileUrl(String path) => path.startsWith('http') ? path : '$apiUrl$path';
