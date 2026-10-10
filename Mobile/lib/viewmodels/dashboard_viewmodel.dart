import 'package:flutter/foundation.dart';

import '../models/dashboard.dart';
import '../models/user.dart';
import '../repositories/dashboard_repository.dart';
import '../repositories/user_repository.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel(this._dashboard, this._users);

  final DashboardRepository _dashboard;
  final UserRepository _users;

  bool isLoading = false;
  String? error;
  User? profile;
  List<User> users = [];
  Stats? stats;
  Duration? loadTime;
  Map<String, Duration> requestTimes = {};

  Duration get sumOfRequests =>
      requestTimes.values.fold(Duration.zero, (sum, time) => sum + time);

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      // The three requests are independent: all start now and we wait for all of them.
      final results = await Future.wait([
        _timed('GET /profile', _dashboard.getProfile),
        _timed('GET /stats', _dashboard.getStats),
        _timed('GET /users', _users.getAll),
      ]);
      profile = results[0] as User;
      stats = results[1] as Stats;
      users = results[2] as List<User>;
      loadTime = stopwatch.elapsed;
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<T> _timed<T>(String name, Future<T> Function() request) async {
    final stopwatch = Stopwatch()..start();
    final result = await request();
    requestTimes[name] = stopwatch.elapsed;
    return result;
  }
}
