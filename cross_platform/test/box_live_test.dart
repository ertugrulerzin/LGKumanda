import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/android_tv/box_client.dart';

import 'helpers.dart';

/// Opt-in: set `LG_BOX_HOST` to the box address and `LG_BOX_CODE_FILE` to a file the person writes the box's code into.
void main() {
  final host = Platform.environment['LG_BOX_HOST'];
  final codeFile = Platform.environment['LG_BOX_CODE_FILE'];
  test('pairs with a real box and sends DOWN then UP', () async {
    final box = BoxClient(storage: MemoryStorage());
    await box.initialize();
    await box.startPairing(host!, 'Tivibu AndroidTV', 'HDMI_3');
    for (var i = 0; i < 150 && box.pairing != BoxPairing.waitingForCode; i++) {
      expect(box.pairing, isNot(BoxPairing.failed), reason: box.pairingError);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(box.pairing, BoxPairing.waitingForCode);
    // ignore: avoid_print
    print('BOX_LIVE waiting for code');
    var code = '';
    for (var i = 0; i < 600 && code.length != 6; i++) {
      final f = File(codeFile!);
      if (f.existsSync()) code = f.readAsStringSync().trim();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    box.finishPairing(code);
    expect(box.pairingError, isNull);
    for (var i = 0; i < 150 && box.pairing != BoxPairing.done; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(box.pairing, BoxPairing.done, reason: box.pairingError);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await box.connect(), isTrue, reason: box.status);
    // ignore: avoid_print
    print('BOX_LIVE connected, model ${box.deviceModel}');
    expect(box.send('DOWN'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(box.send('UP'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    box.dispose();
  }, skip: host == null || codeFile == null ? 'Opt-in' : false, timeout: const Timeout(Duration(minutes: 6)));
}
