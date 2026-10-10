import '../models/user.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class AuthRepository {
  AuthRepository(this._api, this._session);

  final ApiService _api;
  final SessionService _session;

  set onSessionExpired(void Function() callback) =>
      _api.onUnauthorized = callback;

  Future<bool> hasSession() async => await _session.readToken() != null;

  Future<User> login(String email, String password) async {
    final json = await _api.post('/login', {
      'email': email,
      'password': password,
    });
    return _saveSession(json);
  }

  Future<User> register(UserInput input) async {
    final json = await _api.post('/register', input.toJson());
    return _saveSession(json);
  }

  Future<void> logout() => _session.clear();

  Future<User> _saveSession(Map<String, dynamic> json) async {
    await _session.saveToken(json['token']);
    return User.fromJson(json['user']);
  }
}
