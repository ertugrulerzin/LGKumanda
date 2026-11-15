// Android TV Remote protocol v2 (Tivibu and other Android TV boxes): protobuf wire format,
// DER helpers, the client certificate and the pairing secret. Same protocol as the iPhone app
// (LGKumanda/Core/AndroidTV).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);
  Uint8List get bytes => _out.toBytes();
  bool get isEmpty => _out.isEmpty;

  static void writeVarint(BytesBuilder out, int value) {
    var v = value;
    do {
      var byte = v & 0x7f;
      v = v >>> 7;
      if (v != 0) byte |= 0x80;
      out.addByte(byte);
    } while (v != 0);
  }

  void varint(int field, int value) {
    writeVarint(_out, field << 3);
    writeVarint(_out, value);
  }

  void data(int field, List<int> value) {
    writeVarint(_out, field << 3 | 2);
    writeVarint(_out, value.length);
    _out.add(value);
  }

  void string(int field, String value) => data(field, utf8.encode(value));

  void message(int field, void Function(ProtoWriter w) build) {
    final inner = ProtoWriter();
    build(inner);
    data(field, inner.bytes);
  }

  static Uint8List frame(List<int> payload) {
    final out = BytesBuilder(copy: false);
    writeVarint(out, payload.length);
    out.add(payload);
    return out.toBytes();
  }
}

/// Decoded protobuf message: varint fields and length-delimited fields by number.
class ProtoMessage {
  ProtoMessage._(this._varints, this._blobs);
  final Map<int, int> _varints;
  final Map<int, Uint8List> _blobs;

  static ProtoMessage? parse(List<int> bytes) {
    final varints = <int, int>{};
    final blobs = <int, Uint8List>{};
    var i = 0;
    while (i < bytes.length) {
      final key = _readVarint(bytes, i);
      if (key == null) return null;
      i = key.$2;
      final field = key.$1 >> 3;
      switch (key.$1 & 7) {
        case 0:
          final v = _readVarint(bytes, i);
          if (v == null) return null;
          varints[field] = v.$1;
          i = v.$2;
        case 2:
          final len = _readVarint(bytes, i);
          if (len == null || len.$2 + len.$1 > bytes.length) return null;
          blobs[field] = Uint8List.fromList(bytes.sublist(len.$2, len.$2 + len.$1));
          i = len.$2 + len.$1;
        case 1:
          i += 8;
        case 5:
          i += 4;
        default:
          return null;
      }
      if (i > bytes.length) return null;
    }
    return ProtoMessage._(varints, blobs);
  }

  bool has(int field) => _varints.containsKey(field) || _blobs.containsKey(field);
  int? integer(int field) => _varints[field];
  Uint8List? data(int field) => _blobs[field];
  String? string(int field) => _blobs[field] == null ? null : utf8.decode(_blobs[field]!, allowMalformed: true);
  ProtoMessage? message(int field) => _blobs[field] == null ? null : parse(_blobs[field]!);

  /// Returns (value, next index) or null when the varint is incomplete.
  static (int, int)? _readVarint(List<int> b, int start) {
    var result = 0, shift = 0, i = start;
    while (i < b.length && shift < 64) {
      final byte = b[i++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return (result, i);
      shift += 7;
    }
    return null;
  }
}

/// Splits a byte stream into length-prefixed frames.
class ProtoFramer {
  final List<int> _buffer = [];
  List<Uint8List> add(List<int> data) {
    _buffer.addAll(data);
    final frames = <Uint8List>[];
    while (true) {
      final len = ProtoMessage._readVarint(_buffer, 0);
      if (len == null || _buffer.length - len.$2 < len.$1) break;
      frames.add(Uint8List.fromList(_buffer.sublist(len.$2, len.$2 + len.$1)));
      _buffer.removeRange(0, len.$2 + len.$1);
    }
    return frames;
  }
}

/// Minimal DER encoding and decoding for the certificate.
class Der {
  static Uint8List tlv(int tag, List<int> content) {
    final out = BytesBuilder(copy: false)..addByte(tag);
    final n = content.length;
    if (n < 0x80) {
      out.addByte(n);
    } else {
      final len = <int>[];
      for (var v = n; v > 0; v >>= 8) {
        len.insert(0, v & 0xff);
      }
      out.addByte(0x80 | len.length);
      out.add(len);
    }
    out.add(content);
    return out.toBytes();
  }

  static Uint8List sequence(List<List<int>> items) => tlv(0x30, items.expand((e) => e).toList());
  static Uint8List set(List<List<int>> items) => tlv(0x31, items.expand((e) => e).toList());
  static final Uint8List nullValue = Uint8List.fromList([0x05, 0x00]);
  static Uint8List explicit(int tag, List<int> content) => tlv(0xa0 | tag, content);
  static Uint8List bigInt(BigInt v) {
    var bytes = unsignedBytes(v);
    if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
    if (bytes.first & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
    return tlv(0x02, bytes);
  }

  static Uint8List utf8String(String s) => tlv(0x0c, utf8.encode(s));
  static Uint8List bitString(List<int> bytes) => tlv(0x03, [0, ...bytes]);
  static Uint8List oid(List<int> parts) {
    final out = <int>[parts[0] * 40 + parts[1]];
    for (final part in parts.skip(2)) {
      final chunk = <int>[part & 0x7f];
      for (var v = part >> 7; v > 0; v >>= 7) {
        chunk.insert(0, (v & 0x7f) | 0x80);
      }
      out.addAll(chunk);
    }
    return tlv(0x06, out);
  }

  static Uint8List utcTime(DateTime t) {
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return tlv(0x17, ascii.encode('${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
  }

  static Uint8List unsignedBytes(BigInt v) {
    final hex = v.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList([
      for (var i = 0; i < padded.length; i += 2) int.parse(padded.substring(i, i + 2), radix: 16),
    ]);
  }

  /// Reads the TLV at [i]; returns (tag, content start, content end).
  static (int, int, int)? read(List<int> d, int i) {
    if (i + 2 > d.length) return null;
    final tag = d[i];
    var len = d[i + 1];
    var start = i + 2;
    if (len & 0x80 != 0) {
      final count = len & 0x7f;
      if (count > 4 || start + count > d.length) return null;
      len = 0;
      for (var k = 0; k < count; k++) {
        len = len << 8 | d[start + k];
      }
      start += count;
    }
    if (start + len > d.length) return null;
    return (tag, start, start + len);
  }

  /// RSA modulus and exponent from an X.509 certificate (DER).
  static (BigInt, BigInt)? rsaFromCertificate(List<int> der) {
    final cert = read(der, 0);
    if (cert == null) return null;
    final tbs = read(der, cert.$2);
    if (tbs == null) return null;
    var i = tbs.$2;
    final first = read(der, i);
    if (first == null) return null;
    if (first.$1 == 0xa0) i = first.$3; // version
    // serial, signature algorithm, issuer, validity, subject
    for (var k = 0; k < 5; k++) {
      final item = read(der, i);
      if (item == null) return null;
      i = item.$3;
    }
    final spki = read(der, i);
    if (spki == null) return null;
    final algorithm = read(der, spki.$2);
    if (algorithm == null) return null;
    final bits = read(der, algorithm.$3);
    if (bits == null || bits.$1 != 0x03) return null;
    final key = read(der, bits.$2 + 1);
    if (key == null) return null;
    final modulus = read(der, key.$2);
    if (modulus == null) return null;
    final exponent = read(der, modulus.$3);
    if (exponent == null) return null;
    BigInt value((int, int, int) t) => der.sublist(t.$2, t.$3).fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
    return (value(modulus), value(exponent));
  }
}

/// Client identity: RSA key and a self-signed certificate, as PEM for dart:io's SecurityContext.
class BoxIdentity {
  BoxIdentity(this.certificatePem, this.privateKeyPem, this.modulus, this.exponent);
  final String certificatePem, privateKeyPem;
  final BigInt modulus, exponent;

  Map<String, String> toJson() => {'cert': certificatePem, 'key': privateKeyPem};

  static BoxIdentity? fromJson(Map<String, dynamic> j) {
    final cert = j['cert'] as String?, key = j['key'] as String?;
    if (cert == null || key == null) return null;
    final rsa = Der.rsaFromCertificate(_pemBody(cert));
    if (rsa == null) return null;
    return BoxIdentity(cert, key, rsa.$1, rsa.$2);
  }

  static Uint8List _pemBody(String pem) => base64.decode(
    pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join(),
  );

  static String _pem(String label, List<int> der) {
    final b64 = base64.encode(der);
    final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length))];
    return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
  }

  /// Generates a 2048-bit RSA key and a self-signed X.509 certificate (CN=atvremote).
  static BoxIdentity generate() {
    final random = Random.secure();
    final secure = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)))));
    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64), secure));
    final pair = generator.generateKeyPair();
    final pub = pair.publicKey, priv = pair.privateKey;

    final sha256WithRSA = Der.sequence([Der.oid([1, 2, 840, 113549, 1, 1, 11]), Der.nullValue]);
    final name = Der.sequence([
      Der.set([Der.sequence([Der.oid([2, 5, 4, 3]), Der.utf8String('atvremote')])]),
    ]);
    final now = DateTime.now();
    final validity = Der.sequence([
      Der.utcTime(now.subtract(const Duration(days: 1))),
      Der.utcTime(now.add(const Duration(days: 365 * 20))),
    ]);
    final rsaPublicKey = Der.sequence([Der.bigInt(pub.modulus!), Der.bigInt(pub.publicExponent!)]);
    final spki = Der.sequence([
      Der.sequence([Der.oid([1, 2, 840, 113549, 1, 1, 1]), Der.nullValue]),
      Der.bitString(rsaPublicKey),
    ]);
    final serial = BigInt.parse(
      List.generate(15, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    ) + BigInt.one;
    final tbs = Der.sequence([
      Der.explicit(0, Der.bigInt(BigInt.two)),
      Der.bigInt(serial),
      sha256WithRSA,
      name,
      validity,
      name,
      spki,
    ]);
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
    final signature = signer.generateSignature(tbs).bytes;
    final certificate = Der.sequence([tbs, sha256WithRSA, Der.bitString(signature)]);

    final p = priv.p!, q = priv.q!, d = priv.privateExponent!;
    final privateKey = Der.sequence([
      Der.bigInt(BigInt.zero),
      Der.bigInt(priv.modulus!),
      Der.bigInt(pub.publicExponent!),
      Der.bigInt(d),
      Der.bigInt(p),
      Der.bigInt(q),
      Der.bigInt(d % (p - BigInt.one)),
      Der.bigInt(d % (q - BigInt.one)),
      Der.bigInt(q.modInverse(p)),
    ]);
    return BoxIdentity(
      _pem('CERTIFICATE', certificate),
      _pem('RSA PRIVATE KEY', privateKey),
      pub.modulus!,
      pub.publicExponent!,
    );
  }
}

/// SHA-256 over both RSA keys and the last four hex digits of the code shown on the box.
/// Returns null when the first byte does not match the code's first two digits (a typo).
Uint8List? pairingSecret({
  required String code,
  required (BigInt, BigInt) client,
  required (BigInt, BigInt) server,
}) {
  final c = code.trim().toUpperCase();
  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(c)) return null;
  final tail = [int.parse(c.substring(2, 4), radix: 16), int.parse(c.substring(4, 6), radix: 16)];
  final digest = sha256.convert([
    ...Der.unsignedBytes(client.$1),
    ...Der.unsignedBytes(client.$2),
    ...Der.unsignedBytes(server.$1),
    ...Der.unsignedBytes(server.$2),
    ...tail,
  ]).bytes;
  return digest.first == int.parse(c.substring(0, 2), radix: 16) ? Uint8List.fromList(digest) : null;
}

/// Android key codes for the app's LG remote key names; null keeps the key on the TV.
int? androidKeyCode(String lgName) => const {
  'UP': 19, 'DOWN': 20, 'LEFT': 21, 'RIGHT': 22, 'ENTER': 23,
  'HOME': 3, 'BACK': 4, 'EXIT': 4, 'MENU': 82, 'GUIDE': 172, 'INFO': 165, 'QMENU': 176,
  'RED': 183, 'GREEN': 184, 'YELLOW': 185, 'BLUE': 186,
  '0': 7, '1': 8, '2': 9, '3': 10, '4': 11, '5': 12, '6': 13, '7': 14, '8': 15, '9': 16,
  'FLASHBK': 229, 'CC': 175, 'TEXT': 233, 'CHANNELUP': 166, 'CHANNELDOWN': 167,
  'PLAY': 126, 'PAUSE': 127, 'STOP': 86, 'REWIND': 89, 'FASTFORWARD': 90,
}[lgName];
