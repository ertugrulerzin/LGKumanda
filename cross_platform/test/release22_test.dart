import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/android_tv/box_client.dart';
import 'package:lg_kumanda/core/android_tv/box_protocol.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/tv_client.dart';
import 'package:lg_kumanda/core/web_video.dart';

import 'helpers.dart';
import 'box_helpers.dart';

void main() {
  const uuid = 'edf365be-1c48-4995-824c-6ee1bf1b65a4';
  test(
    'legacy single box migrates without losing the shared pairing identity',
    () async {
      final store = MemoryStorage();
      store.values['androidTVBox'] = jsonEncode({
        'host': '192.168.1.11',
        'name': 'Tivibu',
        'paired': true,
        'input': 'HDMI_3',
      });
      store.values['androidTVBox.enabled'] = 'false';
      store.secrets['androidTVBox.identity'] = 'existing identity';
      final box = BoxClient(storage: store);
      addTearDown(box.dispose);
      await box.initialize();
      expect(box.pairedBoxes.length, 1);
      expect(box.enabled, false);
      expect(store.secrets['androidTVBox.identity'], 'existing identity');
      await box.setEnabled(true);
      expect(box.handles('com.webos.app.hdmi3'), true);
      expect(jsonDecode(store.values['androidTVBoxes']!), hasLength(1));
    },
  );
  test('multiple boxes keep input names, custom labels and independent enabled states', () async {
    final store = MemoryStorage();
    store.values['androidTVBoxes'] = jsonEncode([
      {
        'host': '192.168.1.11',
        'name': 'Tivibu',
        'paired': true,
        'input': 'HDMI_3',
      },
      {
        'host': '192.168.1.12',
        'name': 'Google TV',
        'paired': true,
        'input': 'HDMI_4',
      },
    ]);
    final box = BoxClient(storage: store);
    addTearDown(box.dispose);
    await box.initialize();
    expect(box.boxForForeground('com.webos.app.hdmi4')?.host, '192.168.1.12');
    box.select('192.168.1.12');
    await box.rename('Salon kutusu');
    await box.setEnabled(false);
    expect(box.box!.title([const TVItem('HDMI_4', 'TVP')]), 'Salon kutusu');
    expect(box.boxForForeground('com.webos.app.hdmi4'), isNull);
    box.select('192.168.1.11');
    expect(box.enabled, true);
    expect(box.box!.title([const TVItem('HDMI_3', 'Tivibu HD')]), 'Tivibu HD');
    await box.forget();
    expect(box.boxes.single.host, '192.168.1.12');
  });
  test('box waits for RemoteStart, preserves negotiated features and queues commands', () async {
    final store = MemoryStorage();
    store.values['androidTVBoxes'] = jsonEncode([
      {'host': '192.168.1.11', 'name': 'Tivibu', 'paired': true},
    ]);
    final identity = BoxIdentity.generate();
    store.secrets['androidTVBox.identity'] = jsonEncode(identity.toJson());
    final socket = FakeBoxSocket(startAutomatically: false);
    final box = BoxClient(
      storage: store,
      openSocket: (_, _, _) async => socket,
    );
    addTearDown(box.dispose);
    await box.initialize();
    expect(box.send('UP'), true);
    expect(box.playPause(), true);
    await flush();
    expect(socket.activeFeatures, 3);
    expect(socket.keys, isEmpty);
    socket.emit(40, (s) => s.varint(1, 1));
    await flush();
    expect(socket.keys, [19, 85]);
    await box.sendChannel('123');
    await flush();
    expect(socket.keys.sublist(2), [8, 9, 10, 23]);
  });
  test(
    'IP recovery keeps credentials and shortcuts on a stable record ID',
    () async {
      final store = MemoryStorage(), server = FakeTV();
      const tv = Television(host: '192.168.1.3', deviceUUID: uuid);
      store.secrets['key.${tv.storageID}'] = 'old key';
      store.secrets['cert.${tv.storageID}'] = 'test-certificate';
      store.values['shortcuts.${tv.storageID}'] = jsonEncode([
        {'kind': 'app', 'target': 'netflix', 'title': 'Film'},
      ]);
      server.pointerAddress = 'wss://192.168.1.44:3001/resources/pointer';
      final client = TVClient(
        storage: store,
        openSocket: server.open,
        readIdentity: (host, _) async =>
            host == tv.host ? 'another-device' : uuid,
        findAddress: (saved, _) async =>
            copyTelevision(saved, host: '192.168.1.44'),
      );
      addTearDown(client.dispose);
      await client.saveTV(tv);
      await client.connect(tv);
      server.approve();
      await flush();
      expect(client.connected, true);
      expect(client.televisions.single.host, '192.168.1.44');
      expect(client.televisions.single.storageID, tv.storageID);
      expect(client.shortcuts.single.title, 'Film');
      expect(store.secrets['key.${tv.storageID}'], 'test-key');
      expect(store.secrets['key.192.168.1.44'], isNull);
    },
  );
  test(
    'power subscription clears connected state on confirmed standby',
    () async {
      final server = FakeTV();
      final client = TVClient(
        storage: MemoryStorage(),
        openSocket: server.open,
      );
      addTearDown(client.dispose);
      await client.connect(const Television(host: '192.168.1.50'));
      server.approve();
      await flush();
      server.control.receive({
        'id': 'power',
        'type': 'response',
        'payload': {'state': 'Screen Off'},
      });
      await flush();
      expect(client.connected, true);
      server.control.receive({
        'id': 'power',
        'type': 'response',
        'payload': {'state': 'Active Standby'},
      });
      await flush();
      expect(client.connected, false);
      expect(client.connectionLabel, 'TV kapalı');
    },
  );
  test(
    'legacy TV metadata and direct video source validation remain compatible',
    () {
      final legacy = Television.fromJson({'host': '192.168.1.3'});
      expect(legacy.storageID, legacy.host);
      expect(legacy.deviceUUID, isNull);
      final moved = copyTelevision(
        legacy,
        host: '192.168.1.44',
        deviceUUID: uuid,
      );
      expect(moved.storageID, legacy.storageID);
      expect(
        WebVideo.parse({'url': 'https://media.example/movie.m3u8?token=test'})
            ?.mime,
        'application/vnd.apple.mpegurl',
      );
      for (final url in [
        'blob:https://example/id',
        'file:///video.mp4',
        'https://user:pass@example/video.mp4',
        'https://example/page',
      ]) {
        expect(WebVideo.parse({'url': url}), isNull);
      }
    },
  );
}
