import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user.dart';
import '../repositories/file_repository.dart';
import '../repositories/user_repository.dart';
import '../services/image_processing.dart';

class UsersViewModel extends ChangeNotifier {
  UsersViewModel(this._users, this._files);

  final UserRepository _users;
  final FileRepository _files;

  bool isLoading = false;
  String? error;
  List<User> users = [];

  User? byId(int id) => users.where((user) => user.id == id).firstOrNull;

  Future<void> load() => _run(() async => users = await _users.getAll());

  Future<bool> create(UserInput input) => _run(() async {
    users = [...users, await _users.create(input)];
  });

  Future<bool> update(int id, UserInput input) =>
      _run(() async => _replace(await _users.update(id, input)));

  Future<bool> delete(int id) => _run(() async {
    await _users.delete(id);
    users = users.where((user) => user.id != id).toList();
  });

  Future<bool> changePhoto(int id, XFile image) => _run(() async {
    final processed = await processInIsolate(await image.readAsBytes());
    final uploaded = await _files.upload(
      processed.bytes,
      'foto_usuario_$id.jpg',
    );
    _replace(await _users.updatePhoto(id, uploaded.url));
  });

  void _replace(User updated) {
    users = [for (final user in users) user.id == updated.id ? updated : user];
  }

  Future<bool> _run(Future<void> Function() action) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await action();
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
