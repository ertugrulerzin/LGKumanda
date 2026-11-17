import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/android_tv/box_protocol.dart';

void main() {
  test('protobuf round trip and framing', () {
    final w = ProtoWriter()
      ..varint(1, 2)
      ..varint(2, 200)
      ..message(
        10,
        (r) => r
          ..string(1, 'atvremote')
          ..string(2, 'LG Kumanda'),
      );
    final m = ProtoMessage.parse(w.bytes)!;
    expect(m.integer(1), 2);
    expect(m.integer(2), 200);
    expect(m.message(10)!.string(2), 'LG Kumanda');
    final stream = [
      ...ProtoWriter.frame(w.bytes),
      ...ProtoWriter.frame([8, 1]),
    ];
    final framer = ProtoFramer();
    expect(framer.add(stream.sublist(0, 3)), isEmpty);
    final frames = framer.add(stream.sublist(3));
    expect(frames.length, 2);
    expect(frames[0], w.bytes);
    expect(ProtoMessage.parse([0x08]), isNull);
  });

  test('pairing secret matches the reference and rejects typos', () {
    final client = (BigInt.parse('c0ffee' * 10, radix: 16), BigInt.from(65537));
    final server = (BigInt.parse('beef' * 12, radix: 16), BigInt.from(65537));
    final secret = pairingSecret(
      code: '710fec',
      client: client,
      server: server,
    )!;
    expect(
      secret.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '712e735166d8964e455ccf16f43fc9f05658911c3722952588f09b646f3fa98d',
    );
    expect(
      pairingSecret(code: '720FEC', client: client, server: server),
      isNull,
    );
    expect(
      pairingSecret(code: '71ZZZZ', client: client, server: server),
      isNull,
    );
  });

  test('generated identity is a parseable self-signed certificate', () {
    final identity = BoxIdentity.generate();
    expect(identity.certificatePem, startsWith('-----BEGIN CERTIFICATE-----'));
    expect(
      identity.privateKeyPem,
      startsWith('-----BEGIN RSA PRIVATE KEY-----'),
    );
    expect(identity.modulus.bitLength, 2048);
    expect(identity.exponent, BigInt.from(65537));
    final restored = BoxIdentity.fromJson(
      jsonDecode(jsonEncode(identity.toJson())),
    )!;
    expect(restored.modulus, identity.modulus);
    expect(
      () => SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem)),
      returnsNormally,
      reason: 'TLS layer accepts the generated certificate and key',
    );
  });

  test('LG key names map to Android key codes', () {
    expect(androidKeyCode('UP'), 19);
    expect(androidKeyCode('ENTER'), 23);
    expect(androidKeyCode('BACK'), 4);
    expect(androidKeyCode('CHANNELUP'), 166);
    expect(androidKeyCode('5'), 12);
    expect(androidKeyCode('DASH'), isNull);
  });
}
