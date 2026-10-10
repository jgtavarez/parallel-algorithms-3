import 'package:flutter/material.dart';

import '../config.dart';
import '../models/user.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String formatDate(DateTime date) {
  final local = date.toLocal();
  final minutes = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} ${local.hour}:$minutes';
}

String formatDuration(Duration duration) => duration.inMilliseconds < 1000
    ? '${duration.inMilliseconds} ms'
    : '${(duration.inMilliseconds / 1000).toStringAsFixed(2)} s';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 22});

  final User user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = user.photo;
    return CircleAvatar(
      radius: radius,
      backgroundImage: photo != null ? NetworkImage(fileUrl(photo)) : null,
      child: photo == null
          ? Text('${user.firstName[0]}${user.lastName[0]}'.toUpperCase())
          : null,
    );
  }
}
