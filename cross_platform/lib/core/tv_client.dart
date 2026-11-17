import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'network_access.dart';
import 'storage.dart';
import 'transport.dart';
import 'wake_on_lan.dart';
import 'discovery.dart';

class TVClient extends ChangeNotifier {
  TVClient({
    required this.storage,
    this.openSocket = openTVSocket,
    this.ensureNetworkAccess = requireNetworkAccess,
    this.requestTimeout = const Duration(seconds: 10),
    this.readIdentity = readTVIdentity,
    this.findAddress = findMovedTV,
  });
  final TVStorage storage;
  final SocketFactory openSocket;
  final Future<void> Function() ensureNetworkAccess;
  final Duration requestTimeout;
  final Future<String?> Function(String, String) readIdentity;
  final Future<Television?> Function(Television, String) findAddress;
  TVPowerState powerState = TVPowerState.unknown;
  String get connectionLabel =>
      powerState == TVPowerState.standby ? 'TV kapalı' : state.label;
  Timer? _powerTimer, _wakeTimer;
  bool _polling = false,
      _queryPower = true,
      _allowRecovery = true,
      _wakeActive = false;
  DateTime? _wakeDeadline;
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
  String videoDiscoveryScript = '';
  TVSocket? _socket, _pointer;
  Timer? _deadline;
  int _generation = 0, _sequence = 0, _wakeAttempt = 0;
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
          televisions.where((t) => t.storageID == host).firstOrNull ??
          televisions.where((t) => t.host == host).firstOrNull ??
          televisions.firstOrNull;
      if (selected != null) {
        shortcuts = Shortcut.decode(
          await storage.read('shortcuts.${selected!.storageID}'),
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
    final updated = [
      ...televisions.where((e) => e.storageID != tv.storageID),
      tv,
    ];
    await storage.write(
      'televisions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    televisions = updated;
    _emit();
  }

  Future<Television?> savedForDiscovered(Television tv, String? fingerprint) async {
    if (tv.deviceUUID == null || fingerprint == null) return null;
    final matches = <Television>[];
    for (final saved in televisions.where((t) => t.deviceUUID == tv.deviceUUID && t.secure)) {
      if (await storage.readSecret('cert.${saved.storageID}') == fingerprint) matches.add(saved);
    }
    return matches.length == 1 ? copyTelevision(matches.single, host: tv.host) : null;
  }
  Future<void> removeTV(Television tv) async {
    if (selected?.storageID == tv.storageID) {
      disconnect();
      selected = null;
      shortcuts = [];
    }
    await storage.deleteSecret('key.${tv.storageID}');
    await storage.deleteSecret('cert.${tv.storageID}');
    final updated = televisions
        .where((e) => e.storageID != tv.storageID)
        .toList();
    await storage.write(
      'televisions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    await storage.write('shortcuts.${tv.storageID}', '[]');
    televisions = updated;
    _emit();
  }

  Future<void> resetPairing() async {
    final tv = selected;
    if (tv == null) return;
    disconnect();
    await storage.deleteSecret('key.${tv.storageID}');
    await storage.deleteSecret('cert.${tv.storageID}');
    await connect(tv);
  }

  void disconnect({bool preserveWake = false}) {
    _powerTimer?.cancel();
    _powerTimer = null;
    _polling = false;
    powerState = TVPowerState.unknown;
    if (!preserveWake) {
      _wakeTimer?.cancel();
      _wakeTimer = null;
      _wakeActive = false;
      _wakeAttempt++;
    }
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

  Future<void> connect(
    Television tv, {
    bool allowRecovery = true,
    String? credentialID,
    bool fromWake = false,
  }) async {
    disconnect(preserveWake: fromWake);
    _allowRecovery = allowRecovery;
    final source = credentialID ?? tv.storageID;
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
      await storage.write('selected', tv.storageID);
      final key = await storage.readSecret('key.$source');
      final pin = await storage.readSecret('cert.$source');
      final savedShortcuts = Shortcut.decode(
        await storage.read('shortcuts.$source'),
      );
      if (generation != _generation) return;
      shortcuts = savedShortcuts;
      if (tv.secure && tv.deviceUUID != null && pin != null) {
        final uuid = await readIdentity(tv.host, pin);
        if (generation != _generation) return;
        if (uuid != tv.deviceUUID) {
          throw StateError('Kayıtlı TV bu adreste doğrulanamadı.');
        }
      }
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
        (data) => unawaited(_consume(data, generation, tv, socket, source)),
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
      if (e is! LocalNetworkDenied && _allowRecovery && tv.deviceUUID != null) {
        await _recover(tv, generation);
        return;
      }
      if (_wakeActive) {
        disconnect(preserveWake: true);
        return;
      }
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
    final tv = selected;
    if (_allowRecovery &&
        tv?.deviceUUID != null &&
        state != LinkState.pairing) {
      unawaited(_recover(tv!, generation));
      return;
    }
    if (_wakeActive) {
      disconnect(preserveWake: true);
      return;
    }
    disconnect();
    error = 'TV bağlantısı kesildi. TV açılınca yeniden bağlan.';
    _emit();
  }

  void _setDeadline(int generation, Duration duration, String message) {
    _deadline?.cancel();
    _deadline = Timer(duration, () {
      if (generation != _generation) return;
      if (_wakeActive) {
        disconnect(preserveWake: true);
        return;
      }
      final tv = selected;
      if (_allowRecovery &&
          state != LinkState.pairing &&
          tv?.deviceUUID != null) {
        unawaited(_recover(tv!, generation));
        return;
      }
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
    String source,
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
        await storage.writeSecret('key.${tv.storageID}', key);
        if (tv.secure) {
          if (socket.fingerprint == null) {
            throw StateError('TV sertifikası doğrulanamadı.');
          }
          await storage.writeSecret(
            'cert.${tv.storageID}',
            socket.fingerprint!,
          );
        }
        if (generation != _generation) return;
        if (televisions.any(
          (t) => t.storageID == tv.storageID && t.host != tv.host,
        )) {
          await saveTV(tv);
          if (generation != _generation) return;
          notice = 'TV’nin IP adresi otomatik güncellendi.';
        }
        _deadline?.cancel();
        _allowRecovery = true;
        state = LinkState.connected;
        _startPowerMonitor(generation);
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
      } else if (id == 'power') {
        if (type != 'error') _updatePower(p);
      } else if (id == 'foreground') {
        foreground = p['appId'] as String?;
        _emit();
      } else {
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) {
          if (type == 'error' || p['returnValue'] == false) {
            c.completeError(
              TVCommandRejected(
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

  Future<Json> request(
    String uri, [
    Json payload = const {},
    Duration? timeout,
  ]) async {
    if (!connected || _socket == null) {
      throw StateError('Önce bir TV’ye bağlan.');
    }
    final id = 'request-${++_sequence}';
    final c = Completer<Json>();
    _pending[id] = c;
    final timer = Timer(timeout ?? requestTimeout, () {
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
      encodeMessage(
        requestMessage(
          'power',
          'com.webos.service.tvpower/power/getPowerState',
          {},
          true,
        ),
      ),
    );
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
      // The wake identity is captured first and each step is isolated: a
      // failure here (for example reading the TLS identity) must not skip
      // saving the MAC address, or the TV can never be woken.
      await _captureWakeIdentity(generation);
      try {
        await refreshLibrary();
      } catch (_) {}
      try {
        await _captureUUID(generation);
      } catch (_) {
        /* The UUID only helps recover a changed address. */
      }
    }
  }

  void reportError(String reason) {
    error = reason;
    _emit();
  }

  Future<void> _recover(Television tv, int generation) async {
    if (generation != _generation) return;
    final waking = _wakeActive;
    disconnect(preserveWake: waking);
    final token = _generation;
    state = LinkState.connecting;
    notice = 'TV’nin güncel ağ adresi aranıyor…';
    _emit();
    try {
      final pin = await storage.readSecret('cert.${tv.storageID}');
      if (token != _generation) return;
      final found = pin == null ? null : await findAddress(tv, pin);
      if (token != _generation) return;
      if (found != null) {
        await connect(
          found,
          credentialID: tv.storageID,
          allowRecovery: false,
          fromWake: waking,
        );
        return;
      }
      if (waking) {
        disconnect(preserveWake: true);
        return;
      }
      disconnect();
      notice = null;
      error = 'Kayıtlı TV ağda bulunamadı. TV açık ve aynı ağda olmalı.';
      _emit();
    } catch (e) {
      if (token != _generation) return;
      disconnect();
      notice = null;
      error = '$e';
      _emit();
    }
  }

  Future<void> _captureUUID(int generation) async {
    final tv = selected;
    if (tv == null || !tv.secure) return;
    final pin = await storage.readSecret('cert.${tv.storageID}');
    if (pin == null || generation != _generation) return;
    final uuid = await readIdentity(tv.host, pin);
    if (uuid == null || generation != _generation || tv.deviceUUID == uuid) {
      return;
    }
    final updated = copyTelevision(tv, deviceUUID: uuid);
    if (!televisions.any((t) => t.storageID == tv.storageID)) return;
    await saveTV(updated);
    if (generation == _generation && selected?.storageID == tv.storageID) {
      selected = updated;
      _emit();
    }
  }

  void _updatePower(Json payload) {
    final power = readPowerState(payload);
    if (power == TVPowerState.unknown) return;
    if (power == TVPowerState.standby) {
      final waking = _wakeActive;
      disconnect(preserveWake: waking);
      powerState = power;
      notice = waking
          ? 'TV açılıyor…'
          : 'TV kapalı. Uyandır’ı kullanabilirsin.';
    } else {
      powerState = power;
      if (_wakeActive && connected) {
        _wakeTimer?.cancel();
        _wakeTimer = null;
        _wakeActive = false;
        notice = power == TVPowerState.active
            ? 'TV açıldı ve bağlanıldı.'
            : 'TV’ye bağlanıldı; ekran kapalı veya ekran koruyucu etkin.';
      }
    }
    _emit();
  }

  void _startPowerMonitor(int generation) {
    _queryPower = true;
    _powerTimer?.cancel();
    _powerTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_polling || !connected || generation != _generation || !_queryPower) {
        return;
      }
      _polling = true;
      try {
        final result = await request(
          'com.webos.service.tvpower/power/getPowerState',
          const {},
          const Duration(seconds: 3),
        );
        if (generation == _generation) _updatePower(result);
      } on TVCommandRejected {
        _queryPower = false;
        if (_wakeActive) {
          _wakeTimer?.cancel();
          _wakeTimer = null;
          _wakeActive = false;
          notice = 'TV’ye bağlanıldı. Bu model güç durumunu bildirmiyor.';
          _emit();
        }
      } catch (_) {
        _lost(generation);
      } finally {
        if (generation == _generation) _polling = false;
      }
    });
  }

  Future<void> _captureWakeIdentity(int generation) async {
    final tv = selected;
    if (generation != _generation || tv == null || tv.mac.isNotEmpty) return;
    try {
      final info = await request('com.webos.service.connectionmanager/getinfo');
      if (generation != _generation) return;
      Json status = {};
      try {
        status = await request('com.webos.service.connectionmanager/getStatus');
      } catch (_) {
        /* Older firmware may not expose network status. */
      }
      if (generation != _generation ||
          selected?.storageID != tv.storageID ||
          selected!.mac.isNotEmpty) {
        return;
      }
      final updated = wakeIdentity(tv, info, status);
      if (updated == null ||
          !televisions.any((t) => t.host == tv.host && t.mac.isEmpty)) {
        return;
      }
      await saveTV(updated);
      if (generation == _generation && selected?.storageID == tv.storageID) {
        selected = updated;
        _emit();
      }
    } catch (_) {
      /* Wake metadata is optional; normal remote controls still work. */
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
    final host = selected?.storageID;
    if (host == null) return;
    final updated = shortcuts.where((s) => s.id != item.id).toList();
    if (!remove) updated.add(item);
    await storage.write(
      'shortcuts.$host',
      jsonEncode(updated.map((s) => s.toJson()).toList()),
    );
    if (selected?.storageID == host) {
      shortcuts = updated;
      _emit();
    }
  }

  Future<void> reorderShortcuts(List<Shortcut> items) async {
    final host = selected?.storageID;
    if (host == null) return;
    await storage.write(
      'shortcuts.$host',
      jsonEncode(items.map((s) => s.toJson()).toList()),
    );
    if (selected?.storageID == host) {
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
    final generation = _generation;
    await ensureNetworkAccess();
    if (generation != _generation || selected?.storageID != tv.storageID) {
      return;
    }
    if (tv.mac.isEmpty) {
      throw StateError(
        "Uyandırma için TV'nin MAC adresi kayıtlı olmalı. TV'ye bir kez açıkken bağlan; otomatik alınamazsa Cihazı düzenle bölümüne etkin Wi-Fi veya Ethernet MAC adresini gir.",
      );
    }
    final attempt = ++_wakeAttempt;
    error = null;
    notice = 'TV açılıyor…';
    _emit();
    try {
      await sendWakePackets(
        tv,
        cancelled: () => generation != _generation || attempt != _wakeAttempt,
      );
    } catch (_) {
      if (generation != _generation || attempt != _wakeAttempt) return;
      notice = null;
      rethrow;
    }
    if (generation != _generation || attempt != _wakeAttempt) return;
    _wakeActive = true;
    _wakeDeadline = DateTime.now().add(const Duration(seconds: 60));
    _wakeTimer?.cancel();
    _wakeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_wakeActive || _disposed) return;
      if (DateTime.now().isAfter(_wakeDeadline!)) {
        disconnect();
        notice = null;
        error = 'TV’nin açıldığı doğrulanamadı. Mobil ile TV Açma ayarını, MAC adresini ve ağ bağlantısını kontrol et.';
        _emit();
        return;
      }
      if (state == LinkState.disconnected && selected != null) {
        unawaited(connect(selected!, fromWake: true));
      }
    });
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}

class TVCommandRejected implements Exception {
  const TVCommandRejected(this.message);
  final String message;
  @override
  String toString() => message;
}
