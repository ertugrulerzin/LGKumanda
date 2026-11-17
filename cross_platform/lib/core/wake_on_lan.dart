import 'dart:async';
import 'dart:io';

import 'protocol.dart';

String? subnetBroadcast(String host, String mask) {
  int? number(String value) {
    final bytes = value.split('.');
    if (bytes.length != 4) return null;
    var result = 0;
    for (final byte in bytes) {
      final n = int.tryParse(byte);
      if (n == null || n < 0 || n > 255) return null;
      result = (result << 8) | n;
    }
    return result;
  }

  final address = number(host), bits = number(mask);
  if (!isLocalHost(host) || address == null || bits == null || bits == 0) {
    return null;
  }
  final inverse = bits ^ 0xffffffff;
  if (inverse <= 1 || (inverse & (inverse + 1)) != 0) return null;
  final broadcast = (address & bits) | inverse;
  return [24, 16, 8, 0].map((n) => (broadcast >> n) & 255).join('.');
}

Television? wakeIdentity(Television tv, Json info, Json status) {
  final candidates = <String>[];
  for (final adapter in ['wired', 'wifi']) {
    final entry = info['${adapter}Info'];
    if (entry is! Map || entry['macAddress'] is! String) continue;
    final mac = (entry['macAddress'] as String).toUpperCase().replaceAll(
      '-',
      ':',
    );
    try {
      magicPacket(mac);
    } on FormatException {
      continue;
    }
    if (mac == '00:00:00:00:00:00' || mac == 'FF:FF:FF:FF:FF:FF') continue;
    candidates.add(mac);
    final network = status[adapter];
    if (network is Map &&
        network['ipAddress'] == tv.host &&
        network['state'] == 'connected') {
      final mask = network['netmask'];
      return Television(
        host: tv.host,
        deviceUUID: tv.deviceUUID,
        id: tv.storageID,
        name: tv.name,
        secure: tv.secure,
        mac: mac,
        broadcast: tv.broadcast == '255.255.255.255' && mask is String
            ? subnetBroadcast(tv.host, mask) ?? tv.broadcast
            : tv.broadcast,
      );
    }
  }
  if (candidates.length != 1 || status.isNotEmpty) return null;
  return Television(
    host: tv.host,
    deviceUUID: tv.deviceUUID,
    id: tv.storageID,
    name: tv.name,
    secure: tv.secure,
    mac: candidates.single,
    broadcast: tv.broadcast,
  );
}

List<String> wakeTargets(Television tv) {
  if (!isLocalHost(tv.host) ||
      InternetAddress.tryParse(tv.broadcast)?.type !=
          InternetAddressType.IPv4 ||
      !(tv.broadcast == '255.255.255.255' || isLocalHost(tv.broadcast))) {
    throw const FormatException('Geçerli bir yerel yayın IPv4 adresi gir.');
  }
  // A sleeping TV answers no ARP, so only broadcast reaches it. Without a
  // known mask, also try the /24 broadcast: Android may not send the limited
  // broadcast (255.255.255.255) over Wi-Fi, especially with mobile data on.
  final guess = tv.broadcast == '255.255.255.255'
      ? subnetBroadcast(tv.host, '255.255.255.0')
      : null;
  return {tv.host, ?guess, tv.broadcast}.toList();
}

/// The phone's IPv4 address on the TV's network, so packets leave over Wi-Fi.
Future<InternetAddress?> localAddressFacing(String host) async {
  final prefix = host.substring(0, host.lastIndexOf('.') + 1);
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.startsWith(prefix)) return address;
      }
    }
  } on SocketException {
    // Fall back to the default route.
  }
  return null;
}

Future<void> sendWakePackets(
  Television tv, {
  bool Function()? cancelled,
}) async {
  final packet = magicPacket(tv.mac);
  final destinations = wakeTargets(tv);
  final local = await localAddressFacing(tv.host);
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(local ?? InternetAddress.anyIPv4, 0);
  } on SocketException {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }
  try {
    socket.broadcastEnabled = true;
    var delivered = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelled?.call() ?? false) return;
      for (final host in destinations) {
        for (final port in [9, 7]) {
          // Some platforms reject broadcast while still allowing unicast.
          try {
            final count = socket.send(packet, InternetAddress(host), port);
            delivered = delivered || count == packet.length;
          } on SocketException {
            // Try the other destinations before reporting failure.
          }
        }
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (!delivered) {
      throw StateError(
        'Uyandırma paketi gönderilemedi. Wi-Fi bağlantını ve yerel ağ iznini kontrol et.',
      );
    }
  } finally {
    socket.close();
  }
}

/// MAC from the TV's DIAL announcement ("WAKEUP: MAC=d0:cd:...;Timeout=60").
/// LG TVs advertise the address they wake on; this works even when the
/// network-info request is refused.
String? wakeMacFromSsdp(String response) {
  for (final line in response.split(RegExp(r'\r?\n'))) {
    final colon = line.indexOf(':');
    if (colon < 0 ||
        line.substring(0, colon).trim().toUpperCase() != 'WAKEUP') {
      continue;
    }
    final match = RegExp(r'MAC=([0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5})')
        .firstMatch(line.substring(colon + 1));
    if (match == null) continue;
    final mac = match.group(1)!.toUpperCase().replaceAll('-', ':');
    if (mac == '00:00:00:00:00:00' || mac == 'FF:FF:FF:FF:FF:FF') continue;
    return mac;
  }
  return null;
}

/// Asks [host] for its DIAL announcement and returns the wake MAC it reports.
Future<String?> discoverWakeMac(
  String host, {
  Duration wait = const Duration(seconds: 3),
}) async {
  final local = await localAddressFacing(host);
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(local ?? InternetAddress.anyIPv4, 0);
  } on SocketException {
    return null;
  }
  final request =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 1\r\n'
      'ST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n';
  final bytes = request.codeUnits;
  final result = Completer<String?>();
  final timer = Timer(wait, () {
    if (!result.isCompleted) result.complete(null);
  });
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null || datagram.address.address != host) return;
    final mac = wakeMacFromSsdp(String.fromCharCodes(datagram.data));
    if (mac != null && !result.isCompleted) result.complete(mac);
  }, onError: (Object _) {});
  try {
    for (final target in [host, '239.255.255.250']) {
      try {
        socket.send(bytes, InternetAddress(target), 1900);
      } on SocketException {
        // The other target may still work.
      }
    }
    return await result.future;
  } finally {
    timer.cancel();
    await sub.cancel();
    socket.close();
  }
}
