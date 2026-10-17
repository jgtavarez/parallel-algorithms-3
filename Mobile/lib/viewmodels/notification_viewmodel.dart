import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import '../repositories/notification_repository.dart';

class NotificationViewModel extends ChangeNotifier {
  NotificationViewModel(this._notifications);

  final NotificationRepository _notifications;

  bool isSending = false;
  bool? succeeded;
  String? messageId;
  String? error;

  Future<bool> send(EmailInput input) async {
    isSending = true;
    succeeded = null;
    error = null;
    notifyListeners();
    try {
      messageId = await _notifications.send(input);
      succeeded = true;
    } catch (e) {
      error = '$e';
      succeeded = false;
    } finally {
      isSending = false;
      notifyListeners();
    }
    return succeeded!;
  }
}
