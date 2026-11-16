// Native visual verification only. Not used by lib/main.dart or release builds.
// All TV names and catalogs below are synthetic test fixtures.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lg_kumanda/main.dart';
import 'package:lg_kumanda/ui/box_remote.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/tv_client.dart';

import '../test/helpers.dart';
import '../test/box_helpers.dart';

import 'dart:convert';

import 'package:lg_kumanda/core/android_tv/box_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = FakeTV(), storage = MemoryStorage();
  final client = TVClient(
    storage: storage,
    openSocket: server.open,
    ensureNetworkAccess: () async {},
  );
  await storage.write(
    'androidTVBoxes',
    jsonEncode([
      {
        'host': '192.168.1.11',
        'name': 'Tivibu · test verisi',
        'paired': true,
        'input': 'HDMI_3',
      },
      {
        'host': '192.168.1.12',
        'name': 'TVP · test verisi',
        'paired': true,
        'input': 'HDMI_4',
      },
    ]),
  );
  final box = BoxClient(
    storage: storage,
    openSocket: (_, _, _) async => FakeBoxSocket(),
  );
  await box.initialize();
  BoxClient.shared = box;
  client.keyRouter = (key) => box.route(key, client.foreground);
  await client.saveTV(
    const Television(host: '192.168.1.50', name: 'Örnek TV · test verisi'),
  );
  await client.connect(
    const Television(host: '192.168.1.50', name: 'Örnek TV · test verisi'),
  );
  server.approve();
  await flush();
  client.inputs = [
    ...client.inputs,
    const TVItem('HDMI_3', 'Tivibu · test verisi'),
    const TVItem('HDMI_4', 'TVP · test verisi'),
  ];
  final boundary = GlobalKey();
  runApp(
    RepaintBoundary(
      key: boundary,
      child: RemoteApp(client: client),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final folder = await Directory.systemTemp.createTemp(
    'lgkumanda-native-review-',
  );
  Future<void> capture(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  void selectPage(int index) {
    void walk(Element element) {
      final widget = element.widget;
      if (widget is NavigationRail) widget.onDestinationSelected?.call(index);
      if (widget is NavigationBar) widget.onDestinationSelected?.call(index);
      element.visitChildren(walk);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(walk);
  }

  await capture('remote');
  void chooseBox() {
    void walk(Element element) {
      final widget = element.widget;
      if (widget is ChoiceChip &&
          widget.key == const ValueKey('remoteTarget.192.168.1.12')) {
        widget.onSelected?.call(true);
      }
      element.visitChildren(walk);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(walk);
  }

  chooseBox();
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('box-remote');
  void scrollBox(bool bottom) {
    bool moved = false;
    void children(Element element) {
      if (!moved &&
          element is StatefulElement &&
          element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        state.position.jumpTo(bottom ? state.position.maxScrollExtent : 0);
        moved = true;
      }
      if (!moved) element.visitChildren(children);
    }

    void find(Element element) {
      if (element.widget is BoxRemotePage) {
        children(element);
        return;
      }
      element.visitChildren(find);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(find);
  }

  scrollBox(true);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('box-bottom');
  scrollBox(false);
  selectPage(3);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('keyboard');
  selectPage(4);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('devices');
  // Ignore: diagnostic output contains only the local capture directory.
  // ignore: avoid_print
  print('NATIVE_REVIEW_PATH=${folder.path}');
  selectPage(0);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  chooseBox();
}
