import 'dart:async';
import 'dart:convert';

import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/storage.dart';
import 'package:lg_kumanda/core/transport.dart';

class MemoryStorage implements TVStorage {
  final values = <String, String>{}, secrets = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> readSecret(String key) async => secrets[key];
  @override
  Future<void> writeSecret(String key, String value) async {
    if (failWrites) throw StateError('Storage unavailable');
    secrets[key] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    secrets.remove(key);
  }
}

class FakeSocket implements TVSocket {
  FakeSocket({this.fingerprint = 'test-certificate', this.onSend});
  @override
  final String? fingerprint;
  final void Function(String)? onSend;
  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<dynamic> get messages => controller.stream;
  @override
  void send(String text) {
    sent.add(text);
    onSend?.call(text);
  }

  void receive(Json value) => controller.add(jsonEncode(value));
  @override
  Future<void> close() async {
    closed = true;
    unawaited(controller.close());
  }
}

class FakeTV {
  late final FakeSocket control = FakeSocket(
    onSend: (text) {
      final j = jsonDecode(text) as Json;
      if (j['type'] == 'register') return;
      final uri = (j['uri'] as String).replaceFirst('ssap://', '');
      if (uri == 'never/reply') return;
      final payload = switch (uri) {
        'com.webos.service.networkinput/getPointerInputSocket' => {
          'socketPath': pointerAddress,
        },
        'com.webos.applicationManager/listLaunchPoints' => {
          'launchPoints': [
            {'id': 'netflix', 'title': 'Netflix'},
            {'id': 'com.webos.app.browser', 'title': 'Web Browser'},
          ],
        },
        'tv/getExternalInputList' => {
          'devices': [
            {'id': 'HDMI_1', 'label': 'Kutu'},
          ],
        },
        'tv/getChannelList' => {
          'channelList': [
            {
              'channelId': 'ch1',
              'channelName': 'Test kanalı',
              'channelNumber': '1',
            },
          ],
        },
        _ => <String, dynamic>{},
      };
      control.receive({
        'id': j['id'],
        'type': 'response',
        'payload': {'returnValue': true, ...payload},
      });
    },
  );
  final pointer = FakeSocket();
  String pointerAddress = 'wss://192.168.1.50:3001/resources/pointer';
  final pins = <String?>[];
  Future<TVSocket> open(Uri uri, String? fingerprint) async {
    pins.add(fingerprint);
    return uri.path.isEmpty ? control : pointer;
  }

  void approve() => control.receive({
    'type': 'registered',
    'payload': {'client-key': 'test-key'},
  });
}

Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
