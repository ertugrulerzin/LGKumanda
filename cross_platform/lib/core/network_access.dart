import 'dart:io';

import 'package:flutter/services.dart';

class LocalNetworkDenied implements Exception {
  const LocalNetworkDenied();
  @override
  String toString() =>
      'Yerel ağ izni verilmedi. Android ayarlarında LG Kumanda için Yakındaki cihazlar / Yerel ağ iznini aç.';
}

Future<void>? _pendingPermission;
Future<void> requireNetworkAccess() async {
  if (!Platform.isAndroid) return;
  await (_pendingPermission ??= _request().whenComplete(
    () => _pendingPermission = null,
  ));
}

Future<void> _request() async {
  final granted = await const MethodChannel('lgkumanda/network')
      .invokeMethod<bool>('requestLocalNetwork');
  if (granted != true) throw const LocalNetworkDenied();
}
