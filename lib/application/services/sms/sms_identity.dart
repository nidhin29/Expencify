import 'dart:convert';
import 'package:crypto/crypto.dart';

String smsIdentity(String body, DateTime sentAt, {String? sender}) {
  final normalized = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return sha256
      .convert(
        utf8.encode(
          '${sender?.trim().toUpperCase() ?? ''}:${sentAt.millisecondsSinceEpoch}:$normalized',
        ),
      )
      .toString();
}
