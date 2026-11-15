import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'network_access.dart';
import 'storage.dart';
import 'transport.dart';

class TVClient extends ChangeNotifier {
  TVClient({
    required this.storage,
    this.openSocket = openTVSocket,
    this.ensureNetworkAccess = requireNetworkAccess,
    this.requestTimeout = const Duration(seconds: 10),
  });
  final TVStorage storage;
  final SocketFactory openSocket;
  final Future<void> Function() ensureNetworkAccess;
  final Duration requestTimeout;
  List<Television> televisions = [];
  Television? selected;
  LinkState state = LinkState.disconnected;
  List<TVItem> apps = [], inputs = [], channels = [];
  List<Shortcut> shortcuts = [];
  String? error, notice, foreground;
  int? volume;
  bool muted = false, pointerReady = false, loadingLibrary = false;
  ControlMode mode = ControlMode.automatic;
  bool webFocusEnabled = false;
  String webFocusScript = '';
  TVSocket? _socket, _pointer;
  Timer? _deadline;
  int _generation = 0, _sequence = 0;
  bool _registering = false, _disposed = false;
  final Map<String, Completer<Json>> _pending = {};
  Future<void> _keyQueue = Future.value();
  Timer? _motionTimer;
  int _dx = 0, _dy = 0;

  bool get connected => state == LinkState.connected;
  bool get isHDMI => foreground?.startsWith('com.webos.app.hdmi') ?? false;
  bool get useTuner =>
      mode == ControlMode.television ||
      (mode == ControlMode.automatic && foreground == 'com.webos.app.livetv');
  String? get browserID =>
      apps.where((a) => a.id.contains('browser')).firstOrNull?.id;
  bool get browserActive => browserID != null && foreground == browserID;
  TVItem? get hdmiWithoutCEC => isHDMI
      ? inputs
            .where((i) => hdmiAppID(i.id) == foreground && i.simplink == null)
            .firstOrNull
      : null;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final raw = await storage.read('televisions');
      televisions = raw == null
          ? []
          : (jsonDecode(raw) as List)
                .map((e) => Television.fromJson(e as Json))
                .where((t) => isLocalHost(t.host))
                .toList();
      final host = await storage.read('selected');
      selected =
          televisions.where((t) => t.host == host).firstOrNull ??
          televisions.firstOrNull;
      if (selected != null) {
        shortcuts = Shortcut.decode(
          await storage.read('shortcuts.${selected!.host}'),
        );
      }
    } catch (_) {
      error = 'Kayıtlı cihazlar okunamadı. Cihazı yeniden ekleyebilirsin.';
    }
    _emit();
  }

  Future<void> saveTV(Television tv) async {
    if (!isLocalHost(tv.host)) {
      throw const FormatException('Geçerli bir yerel IPv4 adresi gir.');
    }
    final updated = [...televisions.where((e) => e.host != tv.host), tv];
    await storage.write(
      'televisions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    televisions = updated;
    _emit();
  }

  Future<void> removeTV(Television tv) async {
    if (selected?.host == tv.host) {
      disconnect();
      selected = null;
      shortcuts = [];
    }
    await storage.deleteSecret('key.${tv.host}');
    await storage.deleteSecret('cert.${tv.host}');
    final updated = televisions.where((e) => e.host != tv.host).toList();
    await storage.write(
      'televisions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    await storage.write('shortcuts.${tv.host}', '[]');
    televisions = updated;
    _emit();
  }

  Future<void> resetPairing() async {
    final tv = selected;
    if (tv == null) return;
    disconnect();
    await storage.deleteSecret('key.${tv.host}');
    await storage.deleteSecret('cert.${tv.host}');
    await connect(tv);
  }

  void disconnect() {
    _generation++;
    _deadline?.cancel();
    _motionTimer?.cancel();
    _motionTimer = null;
    _dx = 0;
    _dy = 0;
    _registering = false;
    if (_socket != null) unawaited(_socket!.close());
    if (_pointer != null) unawaited(_pointer!.close());
    _socket = null;
    _pointer = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Bağlantı kapandı.'));
    }
    _pending.clear();
    state = LinkState.disconnected;
    pointerReady = false;
    volume = null;
    muted = false;
    foreground = null;
    apps = [];
    inputs = [];
    channels = [];
    loadingLibrary = false;
    _emit();
  }

  Future<void> connect(Television tv) async {
    disconnect();
    error = null;
    notice = null;
    if (!isLocalHost(tv.host)) {
      error = 'TV’nin yerel IPv4 adresini gir.';
      _emit();
      return;
    }
    selected = tv;
    shortcuts = [];
    mode = ControlMode.automatic;
    final generation = _generation;
    state = LinkState.connecting;
    _emit();
    try {
      await ensureNetworkAccess();
      if (generation != _generation) return;
      await storage.write('selected', tv.host);
      final key = await storage.readSecret('key.${tv.host}');
      final pin = await storage.readSecret('cert.${tv.host}');
      final savedShortcuts = Shortcut.decode(
        await storage.read('shortcuts.${tv.host}'),
      );
      if (generation != _generation) return;
      shortcuts = savedShortcuts;
      final socket = await openSocket(
        Uri(
          scheme: tv.secure ? 'wss' : 'ws',
          host: tv.host,
          port: tv.secure ? 3001 : 3000,
        ),
        pin,
      );
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.messages.listen(
        (data) => unawaited(_consume(data, generation, tv, socket)),
        onError: (Object e) => _lost(generation),
        onDone: () => _lost(generation),
        cancelOnError: true,
      );
      socket.send(encodeMessage(registration(key)));
      _setDeadline(
        generation,
        const Duration(seconds: 20),
        'TV’ye ulaşılamadı. IP adresini ve ağ izinlerini kontrol et.',
      );
    } catch (e) {
      if (generation != _generation) return;
      disconnect();
      error = e is LocalNetworkDenied
          ? e.toString()
          : 'Bağlantı kurulamadı. TV’nin açık olduğunu, aynı ağda olduğunu ve ağ izinlerini kontrol et. '
                'Sertifika değiştiyse cihazı doğruladıktan sonra yeniden eşleştir.';
      _emit();
    }
  }

  void _lost(int generation) {
    if (generation != _generation) return;
    disconnect();
    error = 'TV bağlantısı kesildi. TV açılınca yeniden bağlan.';
    _emit();
  }

  void _setDeadline(int generation, Duration duration, String message) {
    _deadline?.cancel();
    _deadline = Timer(duration, () {
      if (generation != _generation) return;
      disconnect();
      error = message;
      _emit();
    });
  }

  Future<void> _consume(
    dynamic data,
    int generation,
    Television tv,
    TVSocket socket,
  ) async {
    if (generation != _generation) return;
    try {
      final j = jsonDecode(
        data is String ? data : utf8.decode(data as List<int>),
      ) as Json;
      final type = j['type'], id = j['id'];
      final p = j['payload'] as Json? ?? {};
      if (type == 'registered' && !connected && !_registering) {
        _registering = true;
        final key = p['client-key'];
        if (key is! String || key.isEmpty) {
          throw StateError('Eşleştirme anahtarı yok.');
        }
        await storage.writeSecret('key.${tv.host}', key);
        if (tv.secure) {
          if (socket.fingerprint == null) {
            throw StateError('TV sertifikası doğrulanamadı.');
          }
          await storage.writeSecret('cert.${tv.host}', socket.fingerprint!);
        }
        if (generation != _generation) return;
        _deadline?.cancel();
        state = LinkState.connected;
        _emit();
        unawaited(_bootstrap(generation));
      } else if (id == 'register' &&
          type == 'response' &&
          !connected &&
          !_registering) {
        state = LinkState.pairing;
        _setDeadline(
          generation,
          const Duration(seconds: 90),
          'Eşleştirme onaylanmadı. TV ekranından bağlantıya izin ver.',
        );
        _emit();
      } else if (id == 'register' && type == 'error') {
        disconnect();
        error = 'TV eşleştirmeyi reddetti. TV ekranından bağlantıya izin ver.';
        _emit();
      } else if (id == 'audio') {
        final audio = p['volumeStatus'] as Json? ?? p;
        volume = audio['volume'] as int? ?? volume;
        muted = audio['mute'] as bool? ?? audio['muted'] as bool? ?? muted;
        _emit();
      } else if (id == 'foreground') {
        foreground = p['appId'] as String?;
        _emit();
      } else {
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) {
          if (type == 'error' || p['returnValue'] == false) {
            c.completeError(
              StateError(
                'TV komutu reddetti: ${j['error'] ?? p['errorText'] ?? 'İşlem desteklenmiyor.'}',
              ),
            );
          } else {
            c.complete(p);
          }
        }
      }
    } catch (_) {
      if (generation == _generation && !connected) {
        disconnect();
        error = 'Eşleştirme güvenle kaydedilemedi. Yeniden dene.';
        _emit();
      }
    }
  }

  Future<Json> request(String uri, [Json payload = const {}]) async {
    if (!connected || _socket == null) {
      throw StateError('Önce bir TV’ye bağlan.');
    }
    final id = 'request-${++_sequence}';
    final c = Completer<Json>();
    _pending[id] = c;
    final timer = Timer(requestTimeout, () {
      if (_pending.remove(id) != null) {
        c.completeError(TimeoutException('TV komuta yanıt vermedi.'));
      }
    });
    try {
      _socket!.send(encodeMessage(requestMessage(id, uri, payload)));
      return await c.future;
    } finally {
      timer.cancel();
      _pending.remove(id);
    }
  }

  Future<void> _bootstrap(int generation) async {
    _socket?.send(
      encodeMessage(requestMessage('audio', 'audio/getVolume', {}, true)),
    );
    _socket?.send(
      encodeMessage(
        requestMessage(
          'foreground',
          'com.webos.applicationManager/getForegroundAppInfo',
          {},
          true,
        ),
      ),
    );
    try {
      final p = await request(
        'com.webos.service.networkinput/getPointerInputSocket',
      );
      if (generation != _generation) return;
      final uri = Uri.tryParse(p['socketPath'] as String? ?? '');
      if (uri == null ||
          uri.host != selected?.host ||
          uri.userInfo.isNotEmpty ||
          !['ws', 'wss'].contains(uri.scheme) ||
          (selected!.secure && uri.scheme != 'wss')) {
        throw StateError('TV güvenli bir işaretçi adresi vermedi.');
      }
      final pointer = await openSocket(uri, _socket?.fingerprint);
      if (generation != _generation) {
        await pointer.close();
        return;
      }
      _pointer = pointer;
      pointerReady = true;
      pointer.messages.listen(
        (_) {},
        onError: (Object e) => _pointerLost(generation),
        onDone: () => _pointerLost(generation),
        cancelOnError: true,
      );
    } catch (_) {
      if (generation == _generation) notice = 'İşaretçi bağlantısı kurulamadı. Bazı kumanda tuşları kullanılamayabilir.';
    }
    if (generation == _generation) {
      _emit();
      await refreshLibrary();
    }
  }

  void _pointerLost(int generation) {
    if (generation != _generation) return;
    pointerReady = false;
    _motionTimer?.cancel();
    _motionTimer = null;
    _dx = 0;
    _dy = 0;
    notice = 'İşaretçi bağlantısı kesildi. Yeniden bağlan.';
    _emit();
  }

  Future<void> refreshLibrary() async {
    if (!connected || loadingLibrary) return;
    final generation = _generation;
    loadingLibrary = true;
    _emit();
    final failures = <String>[];
    for (final spec in [
      (
        'com.webos.applicationManager/listLaunchPoints',
        'launchPoints',
        'Uygulamalar',
      ),
      ('tv/getExternalInputList', 'devices', 'Girişler'),
      ('tv/getChannelList', 'channelList', 'Kanallar'),
    ]) {
      try {
        final p = await request(spec.$1);
        if (generation != _generation) return;
        final rows = (p[spec.$2] as List? ?? [])
            .whereType<Json>()
            .where((e) => e['id'] != null || e['channelId'] != null)
            .map(TVItem.fromJson)
            .toList();
        switch (spec.$2) {
          case 'launchPoints':
            apps = rows..sort((a, b) => a.title.compareTo(b.title));
          case 'devices':
            inputs = rows;
          case 'channelList':
            channels = rows;
        }
      } catch (_) {
        failures.add(spec.$3);
      }
    }
    if (generation != _generation) return;
    loadingLibrary = false;
    if (failures.isNotEmpty) {
      notice = '${failures.join(', ')} okunamadı. Yenile ile tekrar dene.';
    }
    _emit();
  }

  void setMode(ControlMode value) {
    mode = value;
    _emit();
  }

  void setWebFocus(bool value) {
    webFocusEnabled = value;
    _emit();
  }

  void clearMessages() {
    error = null;
    notice = null;
    _emit();
  }

  Future<void> run(Future<void> Function() action) async {
    error = null;
    try {
      await action();
    } catch (e) {
      error = e.toString().replaceFirst('Bad state: ', '');
    }
    _emit();
  }

  void pointer(String text) {
    if (!pointerReady || _pointer == null) {
      throw StateError('İşaretçi bağlantısı hazır değil. Yeniden bağlan.');
    }
    _pointer!.send(text);
  }

  /// Lets another controller (an HDMI box over Wi-Fi) take keys; returns true when it handled the key.
  bool Function(String name)? keyRouter;

  Future<void> key(String name) {
    if (keyRouter?.call(name) == true) return Future.value();
    final generation = _generation;
    final next = _keyQueue.catchError((Object _) {}).then((_) async {
      if (generation != _generation) return;
      final action = {
        'UP': 'up',
        'DOWN': 'down',
        'LEFT': 'left',
        'RIGHT': 'right',
        'ENTER': 'arm',
      }[name];
      if (webFocusEnabled &&
          browserActive &&
          action != null &&
          webFocusScript.isNotEmpty) {
        await request('system.launcher/launch', {
          'id': browserID,
          'params': {
            'target':
                'javascript:${Uri.encodeComponent("${webFocusScript.replaceAll('\n', ' ')}('$action')")}',
          },
        });
        if (name != 'ENTER') return;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (generation == _generation) pointer(buttonMessage(name));
    });
    _keyQueue = next;
    return next;
  }

  Future<void> channel(bool up) async {
    if (useTuner) {
      await request(up ? 'tv/channelUp' : 'tv/channelDown');
    } else {
      await key(up ? 'CHANNELUP' : 'CHANNELDOWN');
    }
  }

  Future<void> media(String action) async {
    if (useTuner) {
      await request('media.controls/$action');
    } else {
      await key(
        {
          'play': 'PLAY',
          'pause': 'PAUSE',
          'stop': 'STOP',
          'rewind': 'REWIND',
          'fastForward': 'FASTFORWARD',
        }[action]!,
      );
    }
  }

  Future<void> activate(String kind, String id) async {
    final items = kind == 'input'
        ? inputs
        : kind == 'channel'
        ? channels
        : apps;
    if (!items.any((e) => e.id == id)) {
      throw StateError('Bu öğe TV’de bulunamadı. Listeyi yenile.');
    }
    await request(
      kind == 'input'
          ? 'tv/switchInput'
          : kind == 'channel'
          ? 'tv/openChannel'
          : 'system.launcher/launch',
      {
        kind == 'input'
                ? 'inputId'
                : kind == 'channel'
                ? 'channelId'
                : 'id':
            id,
      },
    );
    if (kind != 'channel') foreground = kind == 'input' ? hdmiAppID(id) : id;
    _emit();
  }

  Future<void> openBrowser(Uri uri) async {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Geçersiz web adresi.');
    }
    if (browserID == null) {
      throw StateError(
        'TV’nin tarayıcısı bulunamadı. Uygulama listesini yenile.',
      );
    }
    await request('system.launcher/open', {'target': uri.toString()});
    foreground = browserID;
    _emit();
  }

  void move(int dx, int dy) {
    if (!pointerReady) return;
    _dx = (_dx + dx).clamp(-64, 64);
    _dy = (_dy + dy).clamp(-64, 64);
    _motionTimer ??= Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (_dx == 0 && _dy == 0) {
        t.cancel();
        _motionTimer = null;
        return;
      }
      final x = _dx.clamp(-32, 32), y = _dy.clamp(-32, 32);
      _dx -= x;
      _dy -= y;
      try {
        pointer('type:move\ndx:$x\ndy:$y\ndown:0\n\n');
      } catch (_) {
        t.cancel();
        _motionTimer = null;
      }
    });
  }

  void jump(int dx, int dy) {
    var x = dx.clamp(-2000, 2000), y = dy.clamp(-2000, 2000);
    while (x != 0 || y != 0) {
      final sx = x.clamp(-32, 32), sy = y.clamp(-32, 32);
      x -= sx;
      y -= sy;
      pointer('type:move\ndx:$sx\ndy:$sy\ndown:0\n\n');
    }
  }

  Future<void> pin(Shortcut item, {bool remove = false}) async {
    final host = selected?.host;
    if (host == null) return;
    final updated = shortcuts.where((s) => s.id != item.id).toList();
    if (!remove) updated.add(item);
    await storage.write(
      'shortcuts.$host',
      jsonEncode(updated.map((s) => s.toJson()).toList()),
    );
    if (selected?.host == host) {
      shortcuts = updated;
      _emit();
    }
  }

  Future<void> reorderShortcuts(List<Shortcut> items) async {
    final host = selected?.host;
    if (host == null) return;
    await storage.write(
      'shortcuts.$host',
      jsonEncode(items.map((s) => s.toJson()).toList()),
    );
    if (selected?.host == host) {
      shortcuts = items;
      _emit();
    }
  }

  Future<void> powerOff() async {
    if (!connected) throw StateError('Önce bir TV’ye bağlan.');
    _socket!.send(
      encodeMessage(requestMessage('power-${++_sequence}', 'system/turnOff')),
    );
    disconnect();
    notice = 'Kapatma komutu gönderildi.';
    _emit();
  }

  Future<void> wake() async {
    final tv = selected;
    if (tv == null) throw StateError('Önce bir TV seç.');
    await ensureNetworkAccess();
    final packet = magicPacket(tv.mac);
    if (InternetAddress.tryParse(tv.broadcast)?.type !=
            InternetAddressType.IPv4 ||
        !(tv.broadcast == '255.255.255.255' || isLocalHost(tv.broadcast))) {
      throw const FormatException('Geçerli bir yerel yayın IPv4 adresi gir.');
    }
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      final count = socket.send(packet, InternetAddress(tv.broadcast), 9);
      if (count != packet.length) {
        throw StateError('Uyandırma paketi gönderilemedi.');
      }
    } finally {
      socket.close();
    }
    notice = 'Uyandırma paketi gönderildi. TV açılınca yeniden bağlan.';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}
