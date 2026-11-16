import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'protocol.dart';
import 'network_access.dart';
import 'transport.dart';

import 'package:crypto/crypto.dart';

({String name, String? identity})? deviceDescription(String body) {
  try {
    final xml = XmlDocument.parse(body);
    String text(String tag) =>
        xml.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == tag)
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    if (text('manufacturer').toLowerCase() != 'lg electronics' ||
        !xml.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'serviceType')
            .any(
              (e) => e.innerText.contains(
                'urn:lge-com:service:webos-second-screen:',
              ),
            )) {
      return null;
    }
    return (
      name: text('friendlyName').isEmpty ? 'LG webOS TV' : text('friendlyName'),
      identity: text('UDN').isEmpty ? null : text('UDN').toLowerCase(),
    );
  } catch (_) {
    return null;
  }
}

/// True when a TLS certificate subject or issuer belongs to an LG webOS TV
/// (e.g. `/O=LG Electronics Inc./CN=LGE TV SSG`).
bool isLGTelevisionCertificate(String subject, String issuer) {
  bool lg(String value) => value.toLowerCase().contains('lg electronics');
  return lg(subject) || lg(issuer);
}

/// Some webOS TVs keep the 1311 description server closed. They still serve
/// their LG-signed certificate on the remote-control port 3001.
Future<({bool isLG, String fingerprint})?> inspectTelevisionCertificate(
  String host, {
  int port = 3001,
}) async {
  X509Certificate? certificate;
  SecureSocket? socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 1),
      onBadCertificate: (c) {
        certificate = c;
        return true;
      },
    ).timeout(const Duration(seconds: 2));
    final peer = certificate ?? socket.peerCertificate;
    return peer == null
        ? null
        : (
            isLG: isLGTelevisionCertificate(peer.subject, peer.issuer),
            fingerprint: sha256.convert(peer.der).toString(),
          );
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }
}

Future<bool> answersAsLGTelevision(String host, {int port = 3001}) async =>
    (await inspectTelevisionCertificate(host, port: port))?.isLG == true;

class TVDiscovery extends ChangeNotifier {
  bool searching = false;
  int checked = 0, total = 0, _generation = 0;
  String? message;
  List<Television> found = [];
  final fingerprints = <String, String>{};
  HttpClient? _http;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _generation++;
    _http?.close(force: true);
    _http = null;
    searching = false;
    _emit();
  }

  Future<void> search(List<String> knownHosts) async {
    cancel();
    final generation = _generation;
    searching = true;
    found = [];
    fingerprints.clear();
    checked = 0;
    total = 0;
    message = null;
    _emit();
    final http = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 900);
    http.findProxy = (_) => 'DIRECT';
    _http = http;
    try {
      await requireNetworkAccess();
      if (generation != _generation) return;
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final local = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where(isLocalHost)
          .toSet();
      final prefixes = local
          .map((a) => a.substring(0, a.lastIndexOf('.')))
          .toSet()
          .take(4);
      final hosts = {
        ...knownHosts.where(isLocalHost),
        for (final prefix in prefixes)
          for (var i = 1; i < 255; i++) '$prefix.$i',
      }.where((h) => !local.contains(h)).toList();
      if (hosts.isEmpty) {
        message = 'Yerel ağ bulunamadı. TV ile aynı Wi-Fi veya Ethernet ağına bağlan.';
        return;
      }
      total = hosts.length;
      _emit();
      var next = 0;
      final identities = <String>{};
      Future<void> worker() async {
        while (next < hosts.length && generation == _generation) {
          final host = hosts[next++];
          try {
            if (await _identify(http, host, generation, identities)) continue;
            if (generation != _generation) return;
            final certificate = await inspectTelevisionCertificate(host);
            if (certificate?.isLG == true &&
                generation == _generation &&
                !found.any((t) => t.host == host)) {
              final uuid = await readTVIdentity(host, certificate!.fingerprint);
              if (generation != _generation) return;
              fingerprints[host] = certificate.fingerprint;
              found.add(
                Television(host: host, id: uuid ?? host, deviceUUID: uuid),
              );
            }
          } finally {
            if (generation == _generation) {
              checked++;
              _emit();
            }
          }
        }
      }

      await Future.wait(List.generate(24, (_) => worker()));
      if (generation == _generation && found.isEmpty) {
        message = 'TV bulunamadı. TV’yi aç, ağ iznini ve güvenlik duvarını kontrol et veya IP adresiyle ekle.';
      }
    } catch (_) {
      if (generation == _generation) message = 'Ağ taranamadı. Ağ izinlerini kontrol et veya TV’yi IP adresiyle ekle.';
    } finally {
      http.close(force: true);
      if (generation == _generation) {
        searching = false;
        _http = null;
        _emit();
      }
    }
  }

  /// Reads the UPnP description on port 1311. Returns true when that port
  /// answered with an LG description (added to [found]).
  Future<bool> _identify(
    HttpClient http,
    String host,
    int generation,
    Set<String> identities,
  ) async {
    try {
      final request = await http
          .getUrl(Uri.http('$host:1311', '/'))
          .timeout(const Duration(seconds: 1));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      if (response.statusCode != 200) return false;
      final data = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 1))) {
        data.addAll(chunk);
        if (data.length > 65536) return false;
      }
      final description = deviceDescription(utf8.decode(data));
      if (description == null || generation != _generation) return false;
      if (description.identity == null ||
          identities.add(description.identity!)) {
        final certificate = await inspectTelevisionCertificate(host);
        final uuid = certificate == null
            ? null
            : await readTVIdentity(host, certificate.fingerprint);
        if (generation != _generation) return false;
        if (certificate != null) fingerprints[host] = certificate.fingerprint;
        found.add(
          Television(
            host: host,
            id: uuid ?? host,
            name: description.name,
            deviceUUID: uuid,
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

Future<Television?> findMovedTV(Television saved, String fingerprint) async {
  if (saved.deviceUUID == null || !saved.secure) return null;
  final discovery = TVDiscovery();
  try {
    await discovery.search([saved.host]);
    final matches = discovery.found
        .where(
          (t) =>
              t.deviceUUID == saved.deviceUUID &&
              discovery.fingerprints[t.host] == fingerprint,
        )
        .toList();
    if (matches.length > 1) {
      throw StateError(
        'Birden fazla TV eşleşti. Cihazlar’dan doğru TV’yi seç.',
      );
    }
    return matches.isEmpty
        ? null
        : copyTelevision(saved, host: matches.single.host);
  } finally {
    discovery.dispose();
  }
}
