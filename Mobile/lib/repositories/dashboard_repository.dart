import '../models/dashboard.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiService _api;

  Future<User> getProfile() async => User.fromJson(await _api.get('/profile'));

  Future<Stats> getStats() async => Stats.fromJson(await _api.get('/stats'));
}
