import 'package:flutter_test/flutter_test.dart';
import 'package:lg_kumanda/core/protocol.dart';
import 'package:lg_kumanda/core/wake_on_lan.dart';

void main() {
  const tv = Television(host: '192.168.5.40', name: 'Salon');
  final info = <String, dynamic>{
    'wiredInfo': {'macAddress': '20:30:40:50:60:70'},
    'wifiInfo': {'macAddress': 'aa-bb-cc-dd-ee-02'},
  };
  test('uses the NIC serving the paired IP and its actual subnet mask', () {
    final updated = wakeIdentity(tv, info, {
      'wired': {'state': 'disconnected'},
      'wifi': {
        'state': 'connected',
        'ipAddress': tv.host,
        'netmask': '255.255.252.0',
      },
    });
    expect(updated?.mac, 'AA:BB:CC:DD:EE:02');
    expect(updated?.broadcast, '192.168.7.255');
    expect(updated?.name, 'Salon');
    expect(wakeTargets(updated!), ['192.168.5.40', '192.168.7.255']);
  });
  test('adds the /24 broadcast when the subnet mask is unknown', () {
    expect(
      wakeTargets(
        const Television(host: '192.168.1.3', mac: 'D0:CD:BF:5D:FB:9A'),
      ),
      ['192.168.1.3', '192.168.1.255', '255.255.255.255'],
    );
  });
  test('does not guess between inactive interfaces or a different TV IP', () {
    expect(wakeIdentity(tv, info, {}), isNull);
    expect(
      wakeIdentity(tv, info, {
        'wired': {'state': 'connected', 'ipAddress': '192.168.5.41'},
      }),
      isNull,
    );
    expect(
      wakeIdentity(
        tv,
        {'wifiInfo': info['wifiInfo']},
        {
          'wifi': {'state': 'disconnected'},
        },
      ),
      isNull,
    );
  });
  test(
    'supports older firmware with a single NIC but rejects placeholder MACs',
    () {
      expect(
        wakeIdentity(tv, {'wifiInfo': info['wifiInfo']}, {})?.mac,
        'AA:BB:CC:DD:EE:02',
      );
      for (final mac in [
        '',
        'garbage',
        '00:00:00:00:00:00',
        'FF:FF:FF:FF:FF:FF',
      ]) {
        expect(
          wakeIdentity(tv, {
            'wifiInfo': {'macAddress': mac},
          }, {}),
          isNull,
        );
      }
    },
  );
  test('preserves custom broadcast and rejects nonlocal destinations', () {
    const custom = Television(host: '192.168.5.40', broadcast: '192.168.5.255');
    expect(
      wakeIdentity(custom, {'wifiInfo': info['wifiInfo']}, {})?.broadcast,
      custom.broadcast,
    );
    expect(
      () => wakeTargets(const Television(host: '8.8.8.8')),
      throwsFormatException,
    );
    expect(
      () => wakeTargets(
        const Television(host: '192.168.1.3', broadcast: '8.8.8.8'),
      ),
      throwsFormatException,
    );
  });
  test('does not assume a /24 subnet or accept noncontiguous masks', () {
    expect(subnetBroadcast('10.20.30.40', '255.0.0.0'), '10.255.255.255');
    for (final mask in [
      '255.0.255.0',
      '0.0.0.0',
      '255.255.255.255',
      '255.255.255.254',
      'garbage',
    ]) {
      expect(subnetBroadcast(tv.host, mask), isNull);
    }
  });
}
