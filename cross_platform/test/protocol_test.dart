import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/discovery.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/transport.dart';

void main() {
  test('credentials can only be sent to literal private IPv4 addresses', () {
    for (final host in [
      '192.168.1.50',
      '10.0.0.1',
      '172.16.0.1',
      '172.31.255.254',
      '169.254.1.1',
    ]) {
      expect(isLocalHost(host), isTrue);
    }
    for (final host in [
      'example.com',
      '127.0.0.1',
      '8.8.8.8',
      '172.32.0.1',
      '192.168.1.999',
      '192.168.1.1:3001',
      '192.168.1.-1',
      '192.168.1.',
      'https://192.168.1.1',
    ]) {
      expect(isLocalHost(host), isFalse);
    }
  });
  test('certificate pin cannot move to another device or silently rotate', () {
    expect(
      acceptsCertificate(
        expectedHost: '192.168.1.50',
        host: '192.168.1.50',
        actual: 'a',
        saved: null,
      ),
      isTrue,
    );
    expect(
      acceptsCertificate(
        expectedHost: '192.168.1.50',
        host: '192.168.1.50',
        actual: 'a',
        saved: 'a',
      ),
      isTrue,
    );
    expect(
      acceptsCertificate(
        expectedHost: '192.168.1.50',
        host: '192.168.1.50',
        actual: 'b',
        saved: 'a',
      ),
      isFalse,
    );
    expect(
      acceptsCertificate(
        expectedHost: '192.168.1.50',
        host: '192.168.1.51',
        actual: 'a',
        saved: 'a',
      ),
      isFalse,
    );
    expect(
      acceptsCertificate(
        expectedHost: 'example.com',
        host: 'example.com',
        actual: 'a',
        saved: null,
      ),
      isFalse,
    );
  });
  test('browser accepts URLs and searches, rejects executable schemes and userinfo', () {
    expect(browserTarget('example.com').toString(), 'https://example.com');
    expect(browserTarget('LG TV yardım').queryParameters['q'], 'LG TV yardım');
    for (final input in [
      '',
      'javascript:alert(1)',
      'file:///tmp/test',
      'https://user:pass@example.com',
      'https://',
      'https://example.com/\nother',
    ]) {
      expect(() => browserTarget(input), throwsFormatException);
    }
  });
  test('Wake-on-LAN emits the actual 102-byte wire packet', () {
    final p = magicPacket('AA:BB:CC:DD:EE:FF');
    expect(p.length, 102);
    expect(p.take(6), List.filled(6, 255));
    for (var i = 0; i < 16; i++) {
      expect(p.skip(6 + i * 6).take(6), [170, 187, 204, 221, 238, 255]);
    }
    expect(() => magicPacket('not-a-mac'), throwsFormatException);
  });
  test('discovery only accepts LG webOS device descriptions, including XML namespaces', () {
    const xml =
        '<root xmlns="urn:schemas-upnp-org:device-1-0"><device><manufacturer>LG Electronics</manufacturer><friendlyName>Salon &amp; TV</friendlyName><UDN>uuid:TV1</UDN><serviceList><service><serviceType>urn:lge-com:service:webos-second-screen:1</serviceType></service></serviceList></device></root>';
    expect(deviceDescription(xml), (name: 'Salon & TV', identity: 'uuid:tv1'));
    expect(
      deviceDescription(xml.replaceFirst('LG Electronics', 'Other')),
      isNull,
    );
    expect(deviceDescription('<html>LG Electronics</html>'), isNull);
  });
  test(
    'pairing secrets never enter an unauthenticated request or metadata',
    () {
      expect(jsonEncode(registration(null)), isNot(contains('client-key')));
      expect((registration('test')['payload'] as Json)['client-key'], 'test');
      expect(buttonMessage('ENTER'), 'type:button\nname:ENTER\n\n');
      expect(hdmiAppID('HDMI_4'), 'com.webos.app.hdmi4');
    },
  );

  test('pointer reaches the screen centre after pinning to the corner', () {
    final steps = pointerAbsolute(960, 540);
    expect(steps.take(60).every((s) => s == (-32, -32)), isTrue);
    int px(Iterable<int> u) =>
        u.fold(0, (a, v) => a + (v == 32 ? 58 : v == 8 ? 22 : 0));
    expect(px(steps.skip(60).map((s) => s.$1)), 950);
    expect(px(steps.skip(60).map((s) => s.$2)), 544);
  });
}
