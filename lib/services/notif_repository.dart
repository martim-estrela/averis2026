import 'package:cloud_firestore/cloud_firestore.dart';

class NotifRepository {
  NotifRepository._();

  static Future<void> write({
    required String uid,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? metadata,
  }) async {
    final data = <String, dynamic>{
      'type': type,
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (metadata != null) data['metadata'] = metadata;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .add(data);
  }
}
