// Wi-Fi control of an Android TV box (e.g. Tivibu) with the Android TV Remote protocol v2.
// Pairing happens once on port 6467 with a code shown on the box; keys go to port 6466.
// While the TV shows the box's HDMI input, TVClient routes remote keys here instead of HDMI-CEC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../network_access.dart';
import '../protocol.dart';
import '../storage.dart';
import 'box_protocol.dart';

BoxIdentity _generateIdentity(void _) => BoxIdentity.generate();

class SavedBox {
  SavedBox({required this.host, required this.name, this.inputID, this.paired = false});
  final String host, name;
  String? inputID;
  bool paired;
  Map<String, dynamic> toJson() => {'host': host, 'name': name, 'input': inputID, 'paired': paired};
  static SavedBox? fromJson(Map<String, dynamic> j) => j['host'] is String
      ? SavedBox(host: j['host'], name: j['name'] ?? 'Android TV kutusu', inputID: j['input'], paired: j['paired'] == true)
      : null;
}

enum BoxPairing { idle, starting, waitingForCode, verifying, done, failed }

enum BoxLink { idle, connecting, connected, failed }

/// Opens a TLS socket with our client certificate; the box's self-signed certificate is accepted.
typedef BoxSocketFactory = Future<SecureSocket> Function(String host, int port, BoxIdentity identity);

Future<SecureSocket> openBoxSocket(String host, int port, BoxIdentity identity) {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
  return SecureSocket.connect(host, port, context: context, onBadCertificate: (_) => true, timeout: const Duration(seconds: 6));
}

class BoxClient extends ChangeNotifier {
  BoxClient({required this.storage, this.openSocket = openBoxSocket});

  /// The app-wide instance, set in main().
  static BoxClient? shared;
  final TVStorage storage;
  final BoxSocketFactory openSocket;

  static const _boxKey = 'androidTVBox', _enabledKey = 'androidTVBox.enabled', _identityKey = 'androidTVBox.identity';
  static const _features = 1 | 2 | 32 | 64 | 512;

  SavedBox? box;
  bool enabled = true;
  BoxPairing pairing = BoxPairing.idle;
  BoxLink link = BoxLink.idle;
  String? pairingError, linkError, deviceModel;
  BoxIdentity? _identity;
  SecureSocket? _pairSocket, _remoteSocket;
  Completer<bool>? _ready;
  Future<bool>? _connecting;
  bool _disposed = false;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final saved = await storage.read(_boxKey);
    if (saved != null) {
      try {
        box = SavedBox.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {}
    }
    enabled = (await storage.read(_enabledKey)) != 'false';
    _emit();
  }

  Future<void> _save() async {
    await storage.write(_boxKey, box == null ? 'null' : jsonEncode(box!.toJson()));
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await storage.write(_enabledKey, '$value');
    _emit();
  }

  Future<void> linkInput(String? input) async {
    box?.inputID = input;
    await _save();
    _emit();
  }

  /// True when keys for the TV's current foreground app should go to the box.
  bool handles(String? foreground) {
    final b = box;
    if (!enabled || b == null || !b.paired || b.inputID == null) return false;
    return hdmiAppID(b.inputID!) == foreground;
  }

  String get status {
    final name = box?.name ?? 'Kutu';
    return switch (link) {
      BoxLink.connected => '$name Wi-Fi ile kumanda ediliyor.',
      BoxLink.connecting => '$name kutusuna bağlanılıyor…',
      BoxLink.failed => linkError ?? 'Kutuya bağlanılamadı.',
      BoxLink.idle => 'Tuşlar $name kutusuna Wi-Fi ile gönderilecek.',
    };
  }

  Future<BoxIdentity> _loadIdentity() async {
    if (_identity != null) return _identity!;
    final stored = await storage.readSecret(_identityKey);
    if (stored != null) {
      try {
        final identity = BoxIdentity.fromJson(jsonDecode(stored) as Map<String, dynamic>);
        if (identity != null) return _identity = identity;
      } catch (_) {}
    }
    final identity = await compute(_generateIdentity, null);
    await storage.writeSecret(_identityKey, jsonEncode(identity.toJson()));
    return _identity = identity;
  }

  Future<void> forget() async {
    disconnect();
    cancelPairing();
    box = null;
    await _save();
    _emit();
  }

  // Pairing

  Future<void> startPairing(String host, String name, String? inputID) async {
    cancelPairing();
    disconnect();
    pairing = BoxPairing.starting;
    pairingError = null;
    box = SavedBox(host: host, name: name, inputID: inputID ?? box?.inputID);
    await _save();
    _emit();
    try {
      await requireNetworkAccess();
      final socket = await openSocket(host, 6467, await _loadIdentity());
      _pairSocket = socket;
      final framer = ProtoFramer();
      socket.listen(
        (data) {
          for (final frame in framer.add(data)) {
            _onPairing(frame);
          }
        },
        onError: (_) => _pairingClosed(socket),
        onDone: () => _pairingClosed(socket),
      );
      _sendPairing((w) => w.message(10, (r) {
            r.string(1, 'atvremote');
            r.string(2, 'LG Kumanda');
          }));
    } catch (e) {
      _failPairing(_describe(e));
    }
  }

  void finishPairing(String code) {
    final socket = _pairSocket;
    if (pairing != BoxPairing.waitingForCode || socket == null) return;
    final cert = socket.peerCertificate;
    final server = cert == null ? null : Der.rsaFromCertificate(cert.der);
    final identity = _identity;
    if (server == null || identity == null) {
      _failPairing('Kutunun sertifikası okunamadı. Yeniden dene.');
      return;
    }
    final secret = pairingSecret(code: code, client: (identity.modulus, identity.exponent), server: server);
    if (secret == null) {
      pairingError = 'Kod hatalı. Kutunun ekranındaki 6 karakteri kontrol et.';
      _emit();
      return;
    }
    pairingError = null;
    pairing = BoxPairing.verifying;
    _emit();
    _sendPairing((w) => w.message(40, (s) => s.data(1, secret)));
  }

  void cancelPairing() {
    final socket = _pairSocket;
    _pairSocket = null;
    socket?.destroy();
    if (pairing != BoxPairing.done) pairing = BoxPairing.idle;
  }

  void _sendPairing(void Function(ProtoWriter w) build) {
    final w = ProtoWriter()
      ..varint(1, 2)
      ..varint(2, 200);
    build(w);
    _pairSocket?.add(ProtoWriter.frame(w.bytes));
  }

  void _onPairing(Uint8List frame) {
    final m = ProtoMessage.parse(frame);
    if (m == null) return;
    if (m.integer(2) != 200) {
      _failPairing(pairing == BoxPairing.verifying ? 'Kod kabul edilmedi. Yeniden eşleştir.' : 'Kutu eşleştirmeyi reddetti.');
      return;
    }
    void encoding(ProtoWriter e) => e
      ..varint(1, 3)
      ..varint(2, 6);
    if (m.has(11)) {
      _sendPairing((w) => w.message(20, (o) {
            o.message(1, encoding);
            o.varint(3, 1);
          }));
    } else if (m.has(20)) {
      _sendPairing((w) => w.message(30, (c) {
            c.message(1, encoding);
            c.varint(2, 1);
          }));
    } else if (m.has(31)) {
      pairing = BoxPairing.waitingForCode;
      _emit();
    } else if (m.has(41)) {
      pairing = BoxPairing.done;
      box?.paired = true;
      final socket = _pairSocket;
      _pairSocket = null;
      socket?.destroy();
      unawaited(_save());
      _emit();
      unawaited(connect());
    }
  }

  void _pairingClosed(SecureSocket socket) {
    if (_pairSocket != socket) return;
    _pairSocket = null;
    if (pairing != BoxPairing.done && pairing != BoxPairing.idle) _failPairing('Kutu eşleştirmeyi kapattı. Yeniden dene.');
  }

  void _failPairing(String reason) {
    final socket = _pairSocket;
    _pairSocket = null;
    socket?.destroy();
    pairing = BoxPairing.failed;
    pairingError = reason;
    _emit();
  }

  // Remote session

  Future<bool> connect() {
    if (link == BoxLink.connected) return Future.value(true);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<bool> _connect() async {
    final b = box;
    if (b == null || !b.paired) return false;
    link = BoxLink.connecting;
    linkError = null;
    _emit();
    try {
      await requireNetworkAccess();
      final socket = await openSocket(b.host, 6466, await _loadIdentity());
      _remoteSocket = socket;
      final ready = _ready = Completer<bool>();
      final framer = ProtoFramer();
      socket.listen(
        (data) {
          for (final frame in framer.add(data)) {
            _onRemote(frame, socket);
          }
        },
        onError: (_) => _remoteClosed(socket),
        onDone: () => _remoteClosed(socket),
      );
      // The box configures the session first; keys sent before it is active are ignored.
      final ok = await ready.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!ok || _remoteSocket != socket) {
        socket.destroy();
        if (_remoteSocket == socket) _remoteSocket = null;
        link = BoxLink.failed;
        linkError = 'Kutu kumanda oturumunu başlatmadı. Kutu açık mı?';
        _emit();
        return false;
      }
      link = BoxLink.connected;
      _emit();
      return true;
    } catch (e) {
      link = BoxLink.failed;
      linkError = _describe(e);
      _emit();
      return false;
    }
  }

  void disconnect() {
    final socket = _remoteSocket;
    _remoteSocket = null;
    socket?.destroy();
    if (_ready?.isCompleted == false) _ready!.complete(false);
    link = BoxLink.idle;
  }

  /// Sends an LG remote key name to the box. Returns false when the key has no box equivalent.
  bool send(String lgKey) {
    final code = androidKeyCode(lgKey);
    if (code == null) return false;
    unawaited(() async {
      if (!await connect()) return;
      final w = ProtoWriter()..message(10, (k) => k..varint(1, code)..varint(2, 3));
      _remoteSocket?.add(ProtoWriter.frame(w.bytes));
    }());
    return true;
  }

  void _onRemote(Uint8List frame, SecureSocket socket) {
    final m = ProtoMessage.parse(frame);
    if (m == null) return;
    final reply = ProtoWriter();
    final configure = m.message(1);
    if (configure != null) {
      deviceModel = configure.message(2)?.string(1) ?? deviceModel;
      final supported = configure.integer(1) ?? _features;
      reply.message(1, (c) {
        c.varint(1, _features & supported);
        c.message(2, (d) => d
          ..varint(3, 1)
          ..string(4, '1')
          ..string(5, 'atvremote')
          ..string(6, '1.0.0'));
      });
    } else if (m.has(2)) {
      reply.message(2, (a) => a.varint(1, _features));
      if (_ready?.isCompleted == false) _ready!.complete(true);
    } else if (m.has(40)) {
      if (_ready?.isCompleted == false) _ready!.complete(true);
    } else {
      final ping = m.message(8);
      if (ping != null) reply.message(9, (p) => p.varint(1, ping.integer(1) ?? 0));
    }
    if (!reply.isEmpty) socket.add(ProtoWriter.frame(reply.bytes));
  }

  void _remoteClosed(SecureSocket socket) {
    if (_remoteSocket != socket) return;
    _remoteSocket = null;
    if (_ready?.isCompleted == false) _ready!.complete(false);
    link = BoxLink.failed;
    linkError = 'Kutu bağlantısı kapandı.';
    _emit();
  }

  static String _describe(Object e) {
    if (e is LocalNetworkDenied) return e.toString();
    if (e is SocketException) {
      return 'Kutuya ulaşılamadı. Kutu açık ve aynı ağda mı? (${e.osError?.message ?? e.message})';
    }
    if (e is HandshakeException || e is TlsException) return 'Kutu güvenli bağlantıyı kabul etmedi. Yeniden eşleştir.';
    return 'Kutuya bağlanılamadı: $e';
  }

  /// Finds boxes by scanning the local /24 networks for the pairing port.
  static Future<List<String>> scan() async {
    await requireNetworkAccess();
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final local = interfaces.expand((i) => i.addresses).map((a) => a.address).where(isLocalHost).toSet();
    final hosts = {
      for (final a in local)
        for (var i = 1; i < 255; i++) '${a.substring(0, a.lastIndexOf('.'))}.$i',
    }.where((h) => !local.contains(h)).toList();
    final found = <String>[];
    var next = 0;
    Future<void> worker() async {
      while (next < hosts.length) {
        final host = hosts[next++];
        try {
          final s = await Socket.connect(host, 6467, timeout: const Duration(milliseconds: 700));
          s.destroy();
          found.add(host);
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(32, (_) => worker()));
    return found..sort();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    cancelPairing();
    super.dispose();
  }
}
