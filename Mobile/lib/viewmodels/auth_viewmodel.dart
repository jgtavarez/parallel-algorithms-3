import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';

enum AuthStatus { unknown, loggedIn, loggedOut }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository) {
    _repository.onSessionExpired = logout;
  }

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.unknown;
  bool isLoading = false;
  String? error;

  Future<void> restoreSession() async {
    status = await _repository.hasSession()
        ? AuthStatus.loggedIn
        : AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => _repository.login(email, password));

  Future<bool> register(UserInput input) =>
      _authenticate(() => _repository.register(input));

  Future<void> logout() async {
    await _repository.logout();
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<bool> _authenticate(Future<User> Function() action) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await action();
      status = AuthStatus.loggedIn;
      return true;
    } catch (e) {
      error = '$e';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
