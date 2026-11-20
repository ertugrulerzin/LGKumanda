import 'dart:convert';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

bool isLocalHost(String host) {
  final parts = host.split('.');
  if (parts.length != 4 ||
      parts.any((p) => !RegExp(r'^\d{1,3}$').hasMatch(p))) {
    return false;
  }
  final b = parts.map(int.parse).toList();
  if (b.any((n) => n > 255)) return false;
  return b[0] == 10 ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 169 && b[1] == 254);
}

class Television {
  const Television({
    required this.host,
    this.name = 'LG webOS TV',
    this.secure = true,
    this.mac = '',
    this.broadcast = '255.255.255.255',
    this.deviceUUID,
    this.id,
  });
  final String host, name, mac, broadcast;
  final bool secure;
  final String? deviceUUID, id;
  String get storageID => id ?? host;
  Json toJson() => {
    'host': host,
    'name': name,
    'secure': secure,
    'mac': mac,
    'broadcast': broadcast,
    'deviceUUID': deviceUUID,
    'id': storageID,
  };
  factory Television.fromJson(Json j) => Television(
    host: j['host'] as String,
    name: j['name'] as String? ?? 'LG webOS TV',
    secure: j['secure'] as bool? ?? true,
    mac: j['mac'] as String? ?? '',
    broadcast: j['broadcast'] as String? ?? '255.255.255.255',
    deviceUUID: j['deviceUUID'] as String?,
    id: j['id'] as String?,
  );
}

Television copyTelevision(
  Television tv, {
  String? host,
  String? deviceUUID,
  String? mac,
  String? broadcast,
}) => Television(
  id: tv.storageID,
  host: host ?? tv.host,
  name: tv.name,
  secure: tv.secure,
  mac: mac ?? tv.mac,
  broadcast: broadcast ?? tv.broadcast,
  deviceUUID: deviceUUID ?? tv.deviceUUID,
);

enum TVPowerState { unknown, active, standby, screenOff, screenSaver }

TVPowerState readPowerState(Json payload) => switch (payload['state']) {
  'Active' => TVPowerState.active,
  'Active Standby' =>
    (payload['processing'] is String &&
            (payload['processing'] as String).isNotEmpty)
        ? TVPowerState.unknown
        : TVPowerState.standby,
  'Suspend' || 'Power Off' => TVPowerState.standby,
  'Screen Off' => TVPowerState.screenOff,
  'Screen Saver' => TVPowerState.screenSaver,
  _ => TVPowerState.unknown,
};

class TVItem {
  const TVItem(this.id, this.title, {this.detail = '', this.simplink});
  final String id, title, detail;
  final String? simplink;
  factory TVItem.fromJson(Json j) {
    final sub = (j['subList'] as List? ?? []).whereType<Json>();
    final cec =
        sub.where((e) => e['id'] == 'SIMPLINK').firstOrNull ?? sub.firstOrNull;
    return TVItem(
      '${j['id'] ?? j['channelId']}',
      '${j['title'] ?? j['label'] ?? j['channelName'] ?? j['id'] ?? j['channelId']}',
      detail: '${j['channelNumber'] ?? ''}',
      simplink: cec == null ? null : '${cec['osdName'] ?? 'SIMPLINK cihazı'}',
    );
  }
}

enum LinkState { disconnected, connecting, pairing, connected }

extension LinkStateLabel on LinkState {
  String get label => switch (this) {
    LinkState.disconnected => 'Bağlı değil',
    LinkState.connecting => 'Bağlanıyor…',
    LinkState.pairing => 'TV’den onay bekleniyor',
    LinkState.connected => 'Bağlı',
  };
}

enum ControlMode { automatic, television, platform }

extension ControlModeLabel on ControlMode {
  String get label => switch (this) {
    ControlMode.automatic => 'Otomatik',
    ControlMode.television => 'TV kanalları',
    ControlMode.platform => 'Uygulama / HDMI',
  };
}

const permissions = [
  'LAUNCH',
  'CONTROL_AUDIO',
  'CONTROL_INPUT_MEDIA_PLAYBACK',
  'CONTROL_INPUT_TV',
  'CONTROL_POWER',
  'READ_CURRENT_CHANNEL',
  'READ_INPUT_DEVICE_LIST',
  'READ_NETWORK_STATE',
  'READ_RUNNING_APPS',
  'READ_TV_CHANNEL_LIST',
  'READ_POWER_STATE',
  'CONTROL_INPUT_TEXT',
  'CONTROL_MOUSE_AND_KEYBOARD',
  'READ_INSTALLED_APPS',
];
Json registration(String? key) => {
  'id': 'register',
  'type': 'register',
  'payload': {
    'forcePairing': false,
    'pairingType': 'PROMPT',
    'manifest': {
      'manifestVersion': 1,
      'appVersion': '1.0',
      'permissions': permissions,
    },
    'client-key': ?key,
  },
};
Json requestMessage(
  String id,
  String uri, [
  Json payload = const {},
  bool subscribe = false,
]) => {
  'id': id,
  'type': subscribe ? 'subscribe' : 'request',
  'uri': 'ssap://$uri',
  'payload': payload,
};
String buttonMessage(String name) => 'type:button\nname:$name\n\n';

/// Moves that put the pointer at a screen position (1920×1080 pointer space): pin it to the top-left corner, where it
/// clamps, then count steps. Measured on the TV (2026-11-20): a 32-unit move travels 58 px, an 8-unit move 22 px.
List<(int, int)> pointerAbsolute(int x, int y) {
  List<int> plan(int value) {
    final v = value < 0 ? 0 : value;
    final big = v ~/ 58;
    final small = ((v - big * 58) / 22).round();
    return [...List.filled(big, 32), ...List.filled(small, 8)];
  }

  final xs = plan(x), ys = plan(y);
  final steps = List<(int, int)>.filled(60, (-32, -32), growable: true);
  final n = xs.length > ys.length ? xs.length : ys.length;
  for (var i = 0; i < n; i++) {
    steps.add((i < xs.length ? xs[i] : 0, i < ys.length ? ys[i] : 0));
  }
  return steps;
}

Uri browserTarget(String input) {
  final text = input.trim();
  if (text.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(text)) {
    throw const FormatException('Adres veya arama kelimesi yaz.');
  }
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text);
  final address =
      hasScheme || (!text.contains(RegExp(r'\s')) && text.contains('.'));
  // Same language, region and no personalisation on every screen, so the TV
  // and the phone or computer get the same results for the same words.
  if (!address) {
    return Uri.https('www.google.com', '/search', {
      'q': text,
      'hl': 'tr',
      'gl': 'tr',
      'pws': '0',
    });
  }
  final uri = Uri.tryParse(hasScheme ? text : 'https://$text');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Geçerli bir HTTP veya HTTPS adresi yaz.');
  }
  return uri;
}

String? hdmiAppID(String input) {
  final match = RegExp(
    r'^hdmi_?([1-9]\d*)$',
    caseSensitive: false,
  ).firstMatch(input);
  return match == null ? null : 'com.webos.app.hdmi${match[1]}';
}

Uint8List magicPacket(String mac) {
  if (!RegExp(r'^(?:[\da-fA-F]{2}[:-]){5}[\da-fA-F]{2}$').hasMatch(mac)) {
    throw const FormatException('AA:BB:CC:DD:EE:FF biçiminde MAC adresi gir.');
  }
  final bytes = mac
      .split(RegExp('[:-]'))
      .map((s) => int.parse(s, radix: 16))
      .toList();
  return Uint8List.fromList([
    ...List.filled(6, 255),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

String encodeMessage(Json value) => jsonEncode(value);

/// The LG webOS browser's identity. The phone/desktop mirror presents itself
/// the same way so sites (Google above all) serve the page the TV sees.
const webOSBrowserUserAgent =
    'Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/108.0.0.0 Safari/537.36 WebAppManager';
