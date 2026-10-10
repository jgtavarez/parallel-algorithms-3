import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'session_service.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiService {
  ApiService(this._session);

  final SessionService _session;
  final _client = http.Client();
  void Function()? onUnauthorized;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, Object body) => _send('POST', path, body);

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body);

  Future<void> delete(String path) => _send('DELETE', path);

  Future<dynamic> upload(String path, List<int> bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$apiUrl$path'))
      ..headers.addAll(await _headers(json: false))
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    return _execute(request);
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$apiUrl$path'))
      ..headers.addAll(await _headers());
    if (body != null) request.body = jsonEncode(body);
    return _execute(request);
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _session.readToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _execute(http.BaseRequest request) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      throw ApiException(0, 'No se pudo conectar con la API ($apiUrl)');
    }

    final text = utf8.decode(response.bodyBytes);
    dynamic body;
    try {
      body = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      body = text;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    if (response.statusCode == 401) onUnauthorized?.call();
    final message = body is Map && body['error'] != null
        ? body['error'] as String
        : 'Error ${response.statusCode}: $text';
    throw ApiException(response.statusCode, message);
  }
}
