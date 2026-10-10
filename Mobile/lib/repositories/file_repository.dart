import '../models/uploaded_file.dart';
import '../services/api_service.dart';

class FileRepository {
  FileRepository(this._api);

  final ApiService _api;

  Future<List<UploadedFile>> getMine() async {
    final List<dynamic> json = await _api.get('/files');
    return json.map((item) => UploadedFile.fromJson(item)).toList();
  }

  Future<UploadedFile> upload(List<int> bytes, String filename) async =>
      UploadedFile.fromJson(await _api.upload('/upload', bytes, filename));

  Future<void> delete(int id) => _api.delete('/upload/$id');
}
