import '../models/user.dart';
import '../services/api_service.dart';

class UserRepository {
  UserRepository(this._api);

  final ApiService _api;

  Future<List<User>> getAll() async {
    final List<dynamic> json = await _api.get('/users');
    return json.map((item) => User.fromJson(item)).toList();
  }

  Future<User> getById(int id) async =>
      User.fromJson(await _api.get('/users/$id'));

  Future<User> create(UserInput input) async =>
      User.fromJson(await _api.post('/users', input.toJson()));

  Future<User> update(int id, UserInput input) async =>
      User.fromJson(await _api.put('/users/$id', input.toJson()));

  Future<User> updatePhoto(int id, String url) async =>
      User.fromJson(await _api.put('/users/$id', {'photo': url}));

  Future<void> delete(int id) => _api.delete('/users/$id');
}
