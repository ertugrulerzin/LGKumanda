import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/discovery.dart';

void main() {
  test('LG TV certificate is recognised, others are not', () {
    expect(
      isLGTelevisionCertificate(
        '/C=KR/ST=Seoul/O=LG Electronics Inc./OU=HE Lab./CN=LGE TV SSG',
        '/C=KR/ST=Seoul/O=LG Electronics Inc./OU=HE Lab./CN=LGE SSG Intermediate CA',
      ),
      isTrue,
    );
    expect(
      isLGTelevisionCertificate('/CN=router.local', '/CN=router.local'),
      isFalse,
    );
  });

  test('live TV answers on 3001 (opt-in: LG_TV_HOST)', () async {
    final host = Platform.environment['LG_TV_HOST'];
    if (host == null) return;
    final port = int.tryParse(Platform.environment['LG_TV_PORT'] ?? '') ?? 3001;
    expect(await answersAsLGTelevision(host, port: port), isTrue);
  });
}
