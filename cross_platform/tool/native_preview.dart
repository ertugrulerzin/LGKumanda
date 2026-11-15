// Native visual verification only. Not used by lib/main.dart or release builds.
// All TV names and catalogs below are synthetic test fixtures.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lg_kumanda/main.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/tv_client.dart';
import '../test/helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = FakeTV(), storage = MemoryStorage();
  final client = TVClient(storage: storage, openSocket: server.open);
  await client.connect(const Television(host: '192.168.1.50', name: 'Örnek TV · test verisi'));
  server.approve(); await flush();
  final boundary = GlobalKey();
  runApp(RepaintBoundary(key: boundary, child: RemoteApp(client: client)));
  await Future<void>.delayed(const Duration(seconds: 3));
  final folder = await Directory.systemTemp.createTemp('lgkumanda-native-review-');
  Future<void> capture(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final render = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${folder.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
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
  selectPage(3);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('keyboard');
  selectPage(4);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await capture('devices');
  // Ignore: diagnostic output contains only the local capture directory.
  // ignore: avoid_print
  print('NATIVE_REVIEW_PATH=${folder.path}');
}
