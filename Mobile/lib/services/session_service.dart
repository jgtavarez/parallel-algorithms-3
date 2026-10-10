import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionService {
  static const _tokenKey = 'token';
  final _storage = const FlutterSecureStorage();
  String? _token;

  Future<String?> readToken() async =>
      _token ??= await _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clear() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }
}
