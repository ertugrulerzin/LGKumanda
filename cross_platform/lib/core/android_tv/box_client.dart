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
  SavedBox({
    required this.host,
    required this.name,
    String? id,
    this.inputID,
    this.paired = false,
    this.customName = false,
    this.enabled = true,
  }) : id = id ?? host;
  final String id, host;
  String name;
  String? inputID;
  bool paired, customName, enabled;
  String title(List<TVItem> inputs) {
    if (customName && name.trim().isNotEmpty) return name.trim();
    final input = inputs.where((i) => i.id == inputID).firstOrNull;
    if (input != null &&
        input.title.trim().isNotEmpty &&
        input.title.toUpperCase().replaceAll(' ', '_') !=
            inputID?.toUpperCase()) {
      return input.title;
    }
    return name.trim().isNotEmpty
        ? name
        : inputID?.replaceAll('_', ' ') ?? 'Android TV';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'name': name,
    'input': inputID,
    'paired': paired,
    'customName': customName,
    'enabled': enabled,
  };
  static SavedBox? fromJson(Map<String, dynamic> j) =>
      j['host'] is String && isLocalHost(j['host'])
      ? SavedBox(
          id: j['id'],
          host: j['host'],
          name: j['name'] ?? 'Android TV kutusu',
          inputID: j['input'],
          paired: j['paired'] == true,
          customName: j['customName'] == true,
          enabled: j['enabled'] != false,
        )
      : null;
}

enum BoxPairing { idle, starting, waitingForCode, verifying, done, failed }

enum BoxLink { idle, connecting, connected, failed }

/// Opens a TLS socket with our client certificate; the box's self-signed certificate is accepted.
typedef BoxSocketFactory = Future<SecureSocket> Function(
  String host,
  int port,
  BoxIdentity identity,
);

Future<SecureSocket> openBoxSocket(
  String host,
  int port,
  BoxIdentity identity,
) {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
  return SecureSocket.connect(
    host,
    port,
    context: context,
    onBadCertificate: (_) => true,
    timeout: const Duration(seconds: 6),
  );
}

class BoxClient extends ChangeNotifier {
  BoxClient({required this.storage, this.openSocket = openBoxSocket});

  /// The app-wide instance, set in main().
  static BoxClient? shared;
  final TVStorage storage;
  final BoxSocketFactory openSocket;

  static const _boxKey = 'androidTVBoxes',
      _legacyKey = 'androidTVBox',
      _activeKey = 'androidTVBoxes.active',
      _enabledKey = 'androidTVBox.enabled',
      _identityKey = 'androidTVBox.identity';
  // Ping, key, IME (text), power, volume, app links.
  static const _features = 1 | 2 | 4 | 32 | 64 | 512;

  final List<SavedBox> boxes = [];
  String? activeID;
  SavedBox? get box => boxes.where((b) => b.id == activeID).firstOrNull;
  List<SavedBox> get pairedBoxes => boxes.where((b) => b.paired).toList();
  bool get enabled => box?.enabled ?? true;
  bool suspended = false;
  int _generation = 0, _pairGeneration = 0;
  Future<void> _keyQueue = Future.value();
  int _activeFeatures = _features;
  // Counters the box sends for its focused text field; text edits must echo them.
  int _imeCounter = 0, _imeField = 0;
  bool? isOn;
  void Function(String)? onCommandError;
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
    try {
      if (saved != null) {
        final rows = jsonDecode(saved) as List;
        boxes.addAll(
          rows
              .whereType<Map<String, dynamic>>()
              .map(SavedBox.fromJson)
              .whereType<SavedBox>(),
        );
      } else {
        final legacy = await storage.read(_legacyKey);
        if (legacy != null) {
          final row = jsonDecode(legacy);
          final single = row is Map<String, dynamic>
              ? SavedBox.fromJson(row)
              : null;
          if (single != null) {
            single.enabled = await storage.read(_enabledKey) != 'false';
            boxes.add(single);
          }
        }
      }
    } catch (_) {
      pairingError = 'Kayıtlı kutular okunamadı. Yeniden ekleyebilirsin.';
    }
    final selected = await storage.read(_activeKey);
    activeID = boxes.any((b) => b.id == selected)
        ? selected
        : pairedBoxes.firstOrNull?.id;
    await _save();
    _emit();
  }

  Future<void> _save() async {
    await storage.write(
      _boxKey,
      jsonEncode(boxes.map((b) => b.toJson()).toList()),
    );
    await storage.write(_activeKey, activeID ?? '');
  }

  void select(String id) {
    if (activeID == id || !boxes.any((b) => b.id == id)) return;
    cancelPairing();
    disconnect();
    activeID = id;
    unawaited(_save());
    _emit();
  }

  void beginAdding() {
    cancelPairing();
    disconnect();
    activeID = null;
    pairing = BoxPairing.idle;
    _emit();
  }

  Future<void> rename(String name) async {
    box?.name = name.trim();
    box?.customName = name.trim().isNotEmpty;
    await _save();
    _emit();
  }

  Future<void> setEnabled(bool value) async {
    box?.enabled = value;
    if (!value) disconnect();
    await _save();
    _emit();
  }

  Future<void> linkInput(String? input) async {
    box?.inputID = input;
    await _save();
    _emit();
  }

  /// True when keys for the TV's current foreground app should go to the box.
  bool handles(String? foreground) {
    return !suspended && boxForForeground(foreground) != null;
  }

  SavedBox? boxForForeground(String? foreground) => foreground == null
      ? null
      : boxes
            .where(
              (b) =>
                  b.enabled &&
                  b.paired &&
                  b.inputID != null &&
                  hdmiAppID(b.inputID!) == foreground,
            )
            .firstOrNull;
  bool route(String key, String? foreground) {
    final target = boxForForeground(foreground);
    if (suspended || target == null) return false;
    select(target.id);
    return send(key);
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
        final identity = BoxIdentity.fromJson(
          jsonDecode(stored) as Map<String, dynamic>,
        );
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
    boxes.removeWhere((b) => b.id == activeID);
    activeID = pairedBoxes.firstOrNull?.id;
    await _save();
    _emit();
  }

  // Pairing

  Future<void> startPairing(String host, String name, String? inputID) async {
    cancelPairing();
    disconnect();
    pairing = BoxPairing.starting;
    pairingError = null;
    if (!isLocalHost(host)) {
      _failPairing('Geçerli bir yerel IPv4 adresi gir.');
      return;
    }
    final existing = boxes.where((b) => b.host == host).firstOrNull;
    if (existing != null) {
      activeID = existing.id;
      existing.paired = false;
      if (inputID != null) existing.inputID = inputID;
    } else {
      final added = SavedBox(host: host, name: name, inputID: inputID);
      boxes.add(added);
      activeID = added.id;
    }
    final token = _pairGeneration;
    await _save();
    _emit();
    try {
      await requireNetworkAccess();
      final socket = await openSocket(host, 6467, await _loadIdentity());
      if (token != _pairGeneration || _disposed) {
        socket.destroy();
        return;
      }
      _pairSocket = socket;
      final framer = ProtoFramer();
      socket.listen(
        (data) {
          if (_pairSocket != socket || token != _pairGeneration) return;
          for (final frame in framer.add(data)) {
            _onPairing(frame);
          }
        },
        onError: (_) => _pairingClosed(socket),
        onDone: () => _pairingClosed(socket),
      );
      _sendPairing(
        (w) => w.message(10, (r) {
          r.string(1, 'atvremote');
          r.string(2, 'Kumanda');
        }),
      );
    } catch (e) {
      if (token != _pairGeneration) return;
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
    final secret = pairingSecret(
      code: code,
      client: (identity.modulus, identity.exponent),
      server: server,
    );
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
    _pairGeneration++;
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
      _failPairing(
        pairing == BoxPairing.verifying
            ? 'Kod kabul edilmedi. Yeniden eşleştir.'
            : 'Kutu eşleştirmeyi reddetti.',
      );
      return;
    }
    void encoding(ProtoWriter e) => e
      ..varint(1, 3)
      ..varint(2, 6);
    if (m.has(11)) {
      _sendPairing(
        (w) => w.message(20, (o) {
          o.message(1, encoding);
          o.varint(3, 1);
        }),
      );
    } else if (m.has(20)) {
      _sendPairing(
        (w) => w.message(30, (c) {
          c.message(1, encoding);
          c.varint(2, 1);
        }),
      );
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
    if (pairing != BoxPairing.done && pairing != BoxPairing.idle) {
      _failPairing('Kutu eşleştirmeyi kapattı. Yeniden dene.');
    }
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
    final token = _generation;
    return _connecting ??= _connect().whenComplete(() {
      if (token == _generation) _connecting = null;
    });
  }

  Future<bool> _connect() async {
    final b = box;
    if (b == null || !b.paired) return false;
    final token = _generation;
    _activeFeatures = _features;
    link = BoxLink.connecting;
    linkError = null;
    _emit();
    try {
      await requireNetworkAccess();
      final socket = await openSocket(b.host, 6466, await _loadIdentity());
      if (token != _generation || _disposed) {
        socket.destroy();
        return false;
      }
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
      final ok = await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (token != _generation) {
        socket.destroy();
        return false;
      }
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
      if (token != _generation) return false;
      link = BoxLink.failed;
      linkError = _describe(e);
      _emit();
      return false;
    }
  }

  void disconnect() {
    _generation++;
    _connecting = null;
    _keyQueue = Future.value();
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
    return sendCode(code);
  }

  bool sendCode(int code) {
    if (box?.paired != true || !enabled) return false;
    final token = _generation;
    _keyQueue = _keyQueue
        .then((_) async {
          if (token != _generation || _disposed) return;
          if (!await connect()) {
            if (token == _generation) onCommandError?.call(status);
            return;
          }
          if (token != _generation || _disposed) return;
          final w = ProtoWriter()
            ..message(
              10,
              (k) => k
                ..varint(1, code)
                ..varint(2, 3),
            );
          _remoteSocket?.add(ProtoWriter.frame(w.bytes));
        })
        .catchError((Object e) {
          if (token == _generation) onCommandError?.call(_describe(e));
        });
    return true;
  }

  /// Replaces the text in the box's focused text field (Android TV IME).
  bool sendText(String text) {
    if (box?.paired != true || !enabled || text.isEmpty) return false;
    final token = _generation;
    _keyQueue = _keyQueue
        .then((_) async {
          if (token != _generation || _disposed) return;
          if (!await connect()) {
            if (token == _generation) onCommandError?.call(status);
            return;
          }
          if (token != _generation || _disposed) return;
          final w = ProtoWriter()
            ..message(
              21,
              (e) => e
                ..varint(1, _imeCounter)
                ..varint(2, _imeField)
                ..message(
                  3,
                  (i) => i
                    ..varint(1, 1)
                    ..message(
                      2,
                      (f) => f
                        ..varint(1, text.length - 1)
                        ..varint(2, text.length - 1)
                        ..string(3, text),
                    ),
                ),
            );
          _remoteSocket?.add(ProtoWriter.frame(w.bytes));
        })
        .catchError((Object e) {
          if (token == _generation) onCommandError?.call(_describe(e));
        });
    return true;
  }

  bool playPause() => sendCode(85);
  Future<void> sendChannel(String number) async {
    if (!RegExp(r'^\d{1,4}$').hasMatch(number)) {
      throw const FormatException('1–4 haneli kanal numarası gir.');
    }
    for (final digit in number.split('')) {
      send(digit);
    }
    send('ENTER');
    await _keyQueue;
  }

  void _onRemote(Uint8List frame, SecureSocket socket) {
    if (_remoteSocket != socket) return;
    final m = ProtoMessage.parse(frame);
    if (m == null) return;
    final reply = ProtoWriter();
    final configure = m.message(1);
    if (configure != null) {
      deviceModel = configure.message(2)?.string(1) ?? deviceModel;
      final supported = configure.integer(1) ?? _features;
      _activeFeatures = _features & supported;
      reply.message(1, (c) {
        c.varint(1, _activeFeatures);
        c.message(
          2,
          (d) => d
            ..varint(3, 1)
            ..string(4, '1')
            ..string(5, 'atvremote')
            ..string(6, '1.0.0'),
        );
      });
    } else if (m.has(2)) {
      reply.message(2, (a) => a.varint(1, _activeFeatures));
    } else if (m.message(21) case final edit?) {
      _imeCounter = edit.integer(1) ?? _imeCounter;
      _imeField = edit.integer(2) ?? _imeField;
    } else if (m.message(22) case final show?) {
      _imeField = show.message(2)?.integer(1) ?? _imeField;
    } else if (m.has(40)) {
      isOn = m.message(40)?.integer(1) == 1;
      if (_ready?.isCompleted == false) _ready!.complete(true);
    } else {
      final ping = m.message(8);
      if (ping != null) {
        reply.message(9, (p) => p.varint(1, ping.integer(1) ?? 0));
      }
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
    if (e is HandshakeException || e is TlsException) {
      return 'Kutu güvenli bağlantıyı kabul etmedi. Yeniden eşleştir.';
    }
    return 'Kutuya bağlanılamadı: $e';
  }

  /// Finds boxes by scanning the local /24 networks for the pairing port.
  static Future<List<String>> scan() async {
    await requireNetworkAccess();
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final local = interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where(isLocalHost)
        .toSet();
    final hosts = {
      for (final a in local)
        for (var i = 1; i < 255; i++)
          '${a.substring(0, a.lastIndexOf('.'))}.$i',
    }.where((h) => !local.contains(h)).toList();
    final found = <String>[];
    var next = 0;
    Future<void> worker() async {
      while (next < hosts.length) {
        final host = hosts[next++];
        try {
          final s = await Socket.connect(
            host,
            6467,
            timeout: const Duration(milliseconds: 700),
          );
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
