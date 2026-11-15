import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'protocol.dart';

abstract class TVSocket {
  Stream<dynamic> get messages;
  String? get fingerprint;
  void send(String text);
  Future<void> close();
}

typedef SocketFactory = Future<TVSocket> Function(Uri uri, String? fingerprint);

bool acceptsCertificate({
  required String expectedHost,
  required String host,
  required String actual,
  required String? saved,
}) =>
    isLocalHost(expectedHost) &&
    host == expectedHost &&
    (saved == null || actual == saved);

Future<TVSocket> openTVSocket(Uri uri, String? saved) async {
  if (!isLocalHost(uri.host) ||
      !['ws', 'wss'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'TV bağlantısı yalnızca yerel IPv4 adresine kurulabilir.',
    );
  }
  String? fingerprint;
  // Empty trust store ensures even CA-issued certificates go through pin validation.
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = const Duration(seconds: 10);
  client.badCertificateCallback = (cert, host, port) {
    final actual = sha256.convert(cert.der).toString();
    final accept = acceptsCertificate(
      expectedHost: uri.host,
      host: host,
      actual: actual,
      saved: saved,
    );
    if (accept) fingerprint = actual;
    return accept;
  };
  try {
    final ws = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(const Duration(seconds: 12));
    ws.pingInterval = const Duration(seconds: 20);
    return _IOSocket(ws, client, fingerprint);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

class _IOSocket implements TVSocket {
  _IOSocket(this.ws, this.client, this.fingerprint);
  final WebSocket ws;
  final HttpClient client;
  @override
  final String? fingerprint;
  @override
  Stream<dynamic> get messages => ws;
  @override
  void send(String text) => ws.add(text);
  @override
  Future<void> close() async {
    unawaited(ws.close(WebSocketStatus.goingAway));
    client.close(force: true);
  }
}
