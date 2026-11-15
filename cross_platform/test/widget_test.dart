import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lg_kumanda/main.dart';
import 'package:lg_kumanda/core/tv_client.dart';

import 'helpers.dart';

import 'package:lg_kumanda/core/protocol.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('first use and device setup at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = TVClient(storage: MemoryStorage());
      addTearDown(client.dispose);
      await tester.pumpWidget(RemoteApp(client: client));
      await tester.pumpAndSettle();
      expect(find.text('TV kumandan elinin altında'), findsOneWidget);
      await tester.tap(find.text('TV ekle'));
      await tester.pumpAndSettle();
      expect(find.text('TV’ni bağla'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'TV ekle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet ve bağlan'));
      await tester.pumpAndSettle();
      expect(find.text('Geçerli bir yerel IPv4 adresi gir.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('connected remote and keyboard remain usable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage(), server = FakeTV();
      final client = TVClient(storage: storage, openSocket: server.open);
      addTearDown(client.dispose);
      await tester.runAsync(() async {
        await client.connect(const Television(host: '192.168.1.50'));
        server.approve();
        await flush();
      });
      await tester.pumpWidget(RemoteApp(client: client));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      // TV shortcuts must not steal arrow keys from native focused controls.
      final target = find.byType(DropdownButtonFormField<ControlMode>);
      final descendantFocus = find.descendant(
        of: target,
        matching: find.byType(Focus),
      );
      final focusContext = tester.element(descendantFocus.last);
      Focus.of(focusContext).requestFocus();
      await tester.pump();
      final before = server.pointer.sent.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(server.pointer.sent.length, before);
      // The remote surface still handles shortcuts when it owns primary focus.
      final surfaceChild = find
          .descendant(
            of: find.byKey(const ValueKey('remote-keyboard-focus')),
            matching: find.byType(Align),
          )
          .first;
      Focus.of(tester.element(surfaceChild)).requestFocus();
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(server.pointer.sent.last, contains('name:DOWN'));
      Focus.of(tester.element(find.text('Ana ekran'))).requestFocus();
      await tester.pump();
      final buttonBefore = server.pointer.sent.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(server.pointer.sent.length, buttonBefore + 1);
      expect(server.pointer.sent.last, contains('name:HOME'));
      await tester.tap(find.text('Klavye').last);
      await tester.pumpAndSettle();
      expect(find.text('İşaretçisiz'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Merhaba');
      await tester.tap(find.byTooltip('Metni TV’ye gönder'));
      await tester.pumpAndSettle();
      expect(find.text('Metin TV’ye gönderildi.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
