import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/tv_client.dart';

import 'helpers.dart';
import 'package:lg_kumanda/core/transport.dart';

void main() {
  const tv = Television(host: '192.168.1.50');
  test(
    'approved pairing saves secrets securely and loads actual TV catalogs',
    () async {
      final storage = MemoryStorage(), server = FakeTV();
      final client = TVClient(storage: storage, openSocket: server.open);
      addTearDown(client.dispose);
      await client.saveTV(tv);
      await client.connect(tv);
      server.control.receive({'id': 'register', 'type': 'response'});
      await flush();
      expect(client.state, LinkState.pairing);
      expect(storage.secrets, isEmpty);
      server.approve();
      await flush();
      expect(client.connected, isTrue);
      expect(client.pointerReady, isTrue);
      expect(client.apps.map((a) => a.id), contains('netflix'));
      expect(client.inputs.single.id, 'HDMI_1');
      expect(client.channels.single.id, 'ch1');
      expect(storage.secrets['key.${tv.host}'], 'test-key');
      expect(storage.secrets['cert.${tv.host}'], 'test-certificate');
      expect(jsonEncode(storage.values), isNot(contains('test-key')));
      expect(server.pins.last, 'test-certificate');
    },
  );
  test('failed secret storage does not produce a connected UI', () async {
    final storage = MemoryStorage()..failWrites = true;
    final server = FakeTV();
    final client = TVClient(storage: storage, openSocket: server.open);
    addTearDown(client.dispose);
    await client.connect(tv);
    server.approve();
    await flush();
    expect(client.state, LinkState.disconnected);
    expect(client.error, contains('kaydedilemedi'));
  });
  test('HDMI channel keys never accidentally tune the TV', () async {
    final server = FakeTV();
    final client = TVClient(storage: MemoryStorage(), openSocket: server.open);
    addTearDown(client.dispose);
    await client.connect(tv);
    server.approve();
    await flush();
    server.control.receive({
      'id': 'foreground',
      'type': 'response',
      'payload': {'appId': 'com.webos.app.hdmi1'},
    });
    await flush();
    await client.channel(true);
    expect(server.pointer.sent.last, 'type:button\nname:CHANNELUP\n\n');
    expect(server.control.sent.any((s) => s.contains('tv/channelUp')), isFalse);
    client.setMode(ControlMode.television);
    await client.channel(true);
    expect(server.control.sent.last, contains('tv/channelUp'));
  });
  test('disconnect rejects pending requests and a late connect cannot resurrect it', () async {
    final delayed = Completer<TVSocket>();
    final socket = FakeSocket();
    final client = TVClient(
      storage: MemoryStorage(),
      openSocket: (_, _) => delayed.future,
    );
    addTearDown(client.dispose);
    final connecting = client.connect(tv);
    await flush();
    client.disconnect();
    delayed.complete(socket);
    await connecting;
    expect(socket.closed, isTrue);
    expect(client.connected, isFalse);
  });
  test('request deadlines and disconnect are observable failures', () async {
    final server = FakeTV();
    final client = TVClient(
      storage: MemoryStorage(),
      openSocket: server.open,
      requestTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(client.dispose);
    await client.connect(tv);
    server.approve();
    await flush();
    await expectLater(
      client.request('never/reply'),
      throwsA(isA<TimeoutException>()),
    );
    final pending = client.request('never/reply');
    final check = expectLater(pending, throwsStateError);
    client.disconnect();
    await check;
  });
  test(
    'secure control never follows a pointer URL onto another host or cleartext',
    () async {
      for (final path in [
        'wss://192.168.1.51:3001/pointer',
        'ws://192.168.1.50:3000/pointer',
      ]) {
        final server = FakeTV()..pointerAddress = path;
        final client = TVClient(
          storage: MemoryStorage(),
          openSocket: server.open,
        );
        await client.connect(tv);
        server.approve();
        await flush();
        expect(client.connected, isTrue);
        expect(client.pointerReady, isFalse);
        expect(server.pins.length, 1);
        client.dispose();
      }
    },
  );
}
