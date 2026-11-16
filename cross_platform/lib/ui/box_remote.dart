import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/android_tv/box_client.dart';
import '../core/tv_client.dart';
import 'remote.dart';

class BoxRemotePage extends StatefulWidget {
  const BoxRemotePage({
    super.key,
    required this.box,
    required this.saved,
    required this.client,
    required this.openSettings,
  });
  final BoxClient box;
  final SavedBox saved;
  final TVClient client;
  final VoidCallback openSettings;
  @override
  State<BoxRemotePage> createState() => _BoxRemotePageState();
}

class _BoxRemotePageState extends State<BoxRemotePage> {
  String typed = '';
  Timer? _clear;
  final channel = TextEditingController();
  @override
  void dispose() {
    _clear?.cancel();
    channel.dispose();
    super.dispose();
  }

  void send(String key) {
    widget.box.select(widget.saved.id);
    widget.box.send(key);
  }

  void digit(String value) {
    send(value);
    setState(
      () => typed = (typed + value).substring(
        (typed.length + value.length - 4).clamp(0, typed.length + value.length),
      ),
    );
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => typed = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final tv = widget.client;
    Widget key(String text, IconData icon, String name) => RemoteButton(
      label: text,
      icon: icon,
      enabled: widget.saved.enabled,
      onPressed: () => send(name),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!node.hasPrimaryFocus ||
            event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = {
          LogicalKeyboardKey.arrowUp: 'UP',
          LogicalKeyboardKey.arrowDown: 'DOWN',
          LogicalKeyboardKey.arrowLeft: 'LEFT',
          LogicalKeyboardKey.arrowRight: 'RIGHT',
          LogicalKeyboardKey.enter: 'ENTER',
          LogicalKeyboardKey.escape: 'BACK',
        }[event.logicalKey];
        if (key == null || !widget.saved.enabled) return KeyEventResult.ignored;
        send(key);
        return KeyEventResult.handled;
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                widget.saved.title(tv.inputs),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(widget.box.status),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: key('Geri', Icons.undo, 'BACK')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: key('Ana sayfa', Icons.home_outlined, 'HOME'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: key('Menü', Icons.menu, 'MENU')),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 90,
                        child: key('Yukarı', Icons.keyboard_arrow_up, 'UP'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: key(
                              'Sol',
                              Icons.keyboard_arrow_left,
                              'LEFT',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: widget.saved.enabled
                                  ? () => send('ENTER')
                                  : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(80, 80),
                                shape: const CircleBorder(),
                              ),
                              child: const Text('OK'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: key(
                              'Sağ',
                              Icons.keyboard_arrow_right,
                              'RIGHT',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 90,
                        child: key('Aşağı', Icons.keyboard_arrow_down, 'DOWN'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: tv.connected
                          ? () => tv.run(() async {
                              await tv.request('audio/volumeDown');
                            })
                          : null,
                      icon: const Icon(Icons.volume_down_outlined),
                      label: const Text('Ses kıs'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: tv.connected
                          ? () => tv.run(() async {
                              await tv.request('audio/volumeUp');
                            })
                          : null,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Ses aç'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: key('Önceki kanal', Icons.remove, 'CHANNELDOWN'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: key('Sonraki kanal', Icons.add, 'CHANNELUP')),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Kanal', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    typed.isEmpty ? '—' : typed,
                    style: Theme.of(context).textTheme.titleLarge,
                    semanticsLabel: typed.isEmpty
                        ? 'Kanal numarası girilmedi'
                        : 'Girilen kanal $typed',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
                children: [
                  for (final number in [
                    '1',
                    '2',
                    '3',
                    '4',
                    '5',
                    '6',
                    '7',
                    '8',
                    '9',
                  ])
                    OutlinedButton(
                      onPressed: widget.saved.enabled
                          ? () => digit(number)
                          : null,
                      child: Text(number),
                    ),
                  OutlinedButton(
                    onPressed: widget.saved.enabled
                        ? () => send('FLASHBK')
                        : null,
                    child: const Text('Önceki'),
                  ),
                  OutlinedButton(
                    onPressed: widget.saved.enabled ? () => digit('0') : null,
                    child: const Text('0'),
                  ),
                  FilledButton(
                    onPressed: widget.saved.enabled
                        ? () {
                            send('ENTER');
                            setState(() => typed = '');
                          }
                        : null,
                    child: const Text('OK'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: channel,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Kanal numarası',
                      ),
                      onSubmitted: widget.saved.enabled
                          ? (_) => _sendChannel()
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: widget.saved.enabled ? _sendChannel : null,
                    child: const Text('Git'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: key('Geri sar', Icons.fast_rewind, 'REWIND')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RemoteButton(
                      label: 'Duraklat / Devam',
                      icon: Icons.pause,
                      prominent: true,
                      enabled: widget.saved.enabled,
                      onPressed: () {
                        widget.box.select(widget.saved.id);
                        widget.box.playPause();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: key('İleri sar', Icons.fast_forward, 'FASTFORWARD'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: key('Rehber', Icons.list_alt, 'GUIDE')),
                  const SizedBox(width: 8),
                  Expanded(child: key('Bilgi', Icons.info_outline, 'INFO')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: tv.connected
                          ? () => tv.run(() async {
                              await tv.request('audio/setMute', {
                                'mute': !tv.muted,
                              });
                            })
                          : null,
                      child: const Text('Sessiz'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in [
                    ('Kırmızı', 'RED'),
                    ('Yeşil', 'GREEN'),
                    ('Sarı', 'YELLOW'),
                    ('Mavi', 'BLUE'),
                  ])
                    OutlinedButton(
                      onPressed: widget.saved.enabled
                          ? () => send(color.$2)
                          : null,
                      child: Text(color.$1),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: widget.openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Kutu ayarları'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendChannel() async {
    widget.box.select(widget.saved.id);
    await widget.client.run(() => widget.box.sendChannel(channel.text));
  }
}
