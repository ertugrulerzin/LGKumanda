import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lg_kumanda/core/android_tv/box_protocol.dart';

class FakeBoxSocket extends Stream<Uint8List> implements SecureSocket {
  FakeBoxSocket({this.startAutomatically = true}) {
    controller.onListen = () =>
        scheduleMicrotask(() => emit(1, (c) => c.varint(1, 3)));
  }
  final bool startAutomatically;
  final controller = StreamController<Uint8List>();
  final keys = <int>[];
  int? activeFeatures;
  final framer = ProtoFramer();
  void emit(int field, void Function(ProtoWriter) body) {
    if (controller.isClosed) return;
    final w = ProtoWriter()..message(field, body);
    controller.add(ProtoWriter.frame(w.bytes));
  }

  @override
  void add(List<int> data) {
    for (final bytes in framer.add(data)) {
      final m = ProtoMessage.parse(bytes)!;
      if (m.has(1)) emit(2, (a) => a.varint(1, 3));
      if (m.has(2)) {
        activeFeatures = m.message(2)?.integer(1);
        if (startAutomatically) emit(40, (s) => s.varint(1, 1));
      }
      if (m.has(10)) keys.add(m.message(10)!.integer(1)!);
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void destroy() {
    unawaited(controller.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
