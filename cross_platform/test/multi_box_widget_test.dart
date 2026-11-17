import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lg_kumanda/main.dart';
import 'package:lg_kumanda/ui/box_remote.dart';
import 'package:lg_kumanda/core/android_tv/box_client.dart';
import 'package:lg_kumanda/core/android_tv/box_protocol.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/tv_client.dart';

import 'helpers.dart';
import 'box_helpers.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('multiple box tabs and independent controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage(), server = FakeTV();
      storage.values['androidTVBoxes'] = jsonEncode([
        {
          'host': '192.168.1.11',
          'name': 'Android TV',
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
      final sockets = <String, FakeBoxSocket>{};
      late TVClient client;
      late BoxClient box;
      await tester.runAsync(() async {
        storage.secrets['androidTVBox.identity'] = jsonEncode(
          BoxIdentity.generate().toJson(),
        );
        box = BoxClient(
          storage: storage,
          openSocket: (host, _, _) async => sockets[host] = FakeBoxSocket(),
        );
        await box.initialize();
        BoxClient.shared = box;
        client = TVClient(storage: storage, openSocket: server.open);
        await client.connect(const Television(host: '192.168.1.50'));
        server.approve();
        await flush();
        client.inputs = [
          const TVItem('HDMI_3', 'Tivibu'),
          const TVItem('HDMI_4', 'TVP'),
        ];
        client.pointerReady = false;
        box.onCommandError = client.reportError;
        client.keyRouter = (key) => box.route(key, client.foreground);
      });
      addTearDown(() {
        client.dispose();
        box.dispose();
        BoxClient.shared = null;
      });
      await tester.pumpWidget(RemoteApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remoteTarget.192.168.1.12')));
      await tester.runAsync(flush);
      await tester.pumpAndSettle();
      expect(find.byType(BoxRemotePage), findsOneWidget);
      final digit = find.widgetWithText(OutlinedButton, '1');
      await tester.scrollUntilVisible(
        digit,
        220,
        scrollable: find
            .descendant(
              of: find.byType(BoxRemotePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(digit);
      await tester.runAsync(flush);
      await tester.pumpAndSettle();
      expect(sockets['192.168.1.12']?.keys, [8]);
      expect(sockets['192.168.1.11'], isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cihazlar').last);
      await tester.pumpAndSettle();
      expect(find.text('Android TV kutuları'), findsOneWidget);
      expect(find.text('Tivibu'), findsOneWidget);
      expect(find.text('TVP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
