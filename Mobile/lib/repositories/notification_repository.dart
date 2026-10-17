import '../models/notification.dart';
import '../services/api_service.dart';

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiService _api;

  // Returns the Pub/Sub message id.
  Future<String> send(EmailInput input) async {
    final json = await _api.post('/notifications/send', input.toJson());
    return json['messageId'] as String;
  }
}
