import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/android_tv/box_client.dart';
import '../core/protocol.dart';
import '../core/storage.dart';
import '../core/tv_client.dart';
import 'box_setup.dart';
import 'browser.dart';
import 'devices.dart';
import 'shell.dart';

class RemotePage extends StatelessWidget {
  const RemotePage({
    super.key,
    required this.client,
    required this.openDevices,
  });
  final TVClient client;
  final VoidCallback openDevices;
  @override
  Widget build(BuildContext context) {
    if (client.selected == null) {
      return EmptyState(
        icon: Icons.tv,
        title: 'TV kumandan elinin altında',
        message: 'LG webOS TV’ni ekle. Ses, kanallar, uygulamalar ve telefon klavyesi tek yerde olsun.',
        action: FilledButton.icon(
          onPressed: openDevices,
          icon: const Icon(Icons.add),
          label: const Text('TV ekle'),
        ),
      );
    }
    void key(String key) => client.run(() => client.key(key));
    Widget remoteKey(String title, IconData icon, String name) => RemoteButton(
      label: title,
      icon: icon,
      enabled: client.connected && client.pointerReady,
      onPressed: () => key(name),
    );
    return Focus(
      key: const ValueKey('remote-keyboard-focus'),
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final name = {
          LogicalKeyboardKey.arrowUp: 'UP',
          LogicalKeyboardKey.arrowDown: 'DOWN',
          LogicalKeyboardKey.arrowLeft: 'LEFT',
          LogicalKeyboardKey.arrowRight: 'RIGHT',
          LogicalKeyboardKey.enter: 'ENTER',
          LogicalKeyboardKey.escape: 'BACK',
        }[event.logicalKey];
        if (name == null || !client.connected || !client.pointerReady) {
          return KeyEventResult.ignored;
        }
        key(name);
        return KeyEventResult.handled;
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              if (!client.connected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TV açıkken bağlan. Eşleştirme isteği çıkarsa TV ekranından onayla.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: client.state == LinkState.disconnected
                            ? () => client.connect(client.selected!)
                            : null,
                        icon: const Icon(Icons.link),
                        label: const Text('TV’ye bağlan'),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      client.selected!.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'TV’yi kapat',
                    onPressed: client.connected
                        ? () async {
                            if (await confirm(
                              context,
                              'TV kapatılsın mı?',
                              'TV’yi yeniden açmak için fiziksel kumanda veya destekleniyorsa uyandırma kullanılabilir.',
                            )) {
                              await client.run(client.powerOff);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.power_settings_new),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: remoteKey('Ana ekran', Icons.home_outlined, 'HOME'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: remoteKey('Geri', Icons.undo, 'BACK')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: remoteKey(
                      'Ayarlar',
                      Icons.settings_outlined,
                      'QMENU',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ControlMode>(
                initialValue: client.mode,
                decoration: const InputDecoration(labelText: 'Kontrol hedefi'),
                items: [
                  for (final m in ControlMode.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: client.connected ? (m) => client.setMode(m!) : null,
              ),
              if (BoxClient.shared case final box? when client.isHDMI)
                ListenableBuilder(
                  listenable: box,
                  builder: (context, _) {
                    final handled = box.handles(client.foreground);
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!handled && client.hdmiWithoutCEC != null)
                            Text(
                              '${client.hdmiWithoutCEC!.title} girişinde SIMPLINK cihazı görünmüyor. Kutu yön tuşlarına yanıt vermeyebilir.',
                            ),
                          if (handled) Row(children: [const Icon(Icons.wifi, size: 18), const SizedBox(width: 8), Expanded(child: Text(box.status))]),
                          TextButton.icon(
                            key: const Key('openBoxSetup'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => BoxSetupPage(box: box, client: client)),
                            ),
                            icon: const Icon(Icons.router_outlined),
                            label: Text(box.box?.paired == true ? 'Wi-Fi ile kutu kumandası' : 'Kutuyu Wi-Fi ile kumanda et'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          Expanded(
                            flex: 2,
                            child: remoteKey(
                              'Yukarı',
                              Icons.keyboard_arrow_up,
                              'UP',
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: remoteKey(
                              'Sol',
                              Icons.keyboard_arrow_left,
                              'LEFT',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: client.connected && client.pointerReady
                                  ? () => key('ENTER')
                                  : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(80, 88),
                                shape: const CircleBorder(),
                              ),
                              child: const Text('OK'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: remoteKey(
                              'Sağ',
                              Icons.keyboard_arrow_right,
                              'RIGHT',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          Expanded(
                            flex: 2,
                            child: remoteKey(
                              'Aşağı',
                              Icons.keyboard_arrow_down,
                              'DOWN',
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Ses ${client.volume ?? '—'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        RemoteButton(
                          label: 'Ses aç',
                          icon: Icons.volume_up_outlined,
                          enabled: client.connected,
                          onPressed: () => client.run(() async {
                            await client.request('audio/volumeUp');
                          }),
                        ),
                        const SizedBox(height: 8),
                        RemoteButton(
                          label: 'Ses kıs',
                          icon: Icons.volume_down_outlined,
                          enabled: client.connected,
                          onPressed: () => client.run(() async {
                            await client.request('audio/volumeDown');
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Kanal',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        RemoteButton(
                          label: 'Sonraki',
                          icon: Icons.add,
                          enabled: client.connected,
                          onPressed: () =>
                              client.run(() => client.channel(true)),
                        ),
                        const SizedBox(height: 8),
                        RemoteButton(
                          label: 'Önceki',
                          icon: Icons.remove,
                          enabled: client.connected,
                          onPressed: () =>
                              client.run(() => client.channel(false)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: client.connected
                    ? () => client.run(() async {
                        await client.request('audio/setMute', {
                          'mute': !client.muted,
                        });
                      })
                    : null,
                icon: Icon(client.muted ? Icons.volume_off : Icons.volume_mute),
                label: Text(client.muted ? 'Sesi aç' : 'Sessize al'),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in [
                    ('rewind', Icons.fast_rewind, 'Geri sar'),
                    ('play', Icons.play_arrow, 'Oynat'),
                    ('pause', Icons.pause, 'Duraklat'),
                    ('stop', Icons.stop, 'Durdur'),
                    ('fastForward', Icons.fast_forward, 'İleri sar'),
                  ])
                    IconButton.filledTonal(
                      tooltip: action.$3,
                      onPressed: client.connected
                          ? () => client.run(() => client.media(action.$1))
                          : null,
                      icon: Icon(action.$2),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kısayollar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kısayolları düzenle',
                    onPressed: client.shortcuts.isEmpty
                        ? null
                        : () => _editShortcuts(context),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              if (client.shortcuts.isEmpty)
                const Text(
                  'Uygulamalar veya HDMI / Girişler listesindeki yıldızla favorilerini buraya ekle.',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in client.shortcuts)
                    OutlinedButton.icon(
                      onPressed: client.connected
                          ? () => client.run(
                              () => client.activate(s.kind, s.target),
                            )
                          : null,
                      icon: Icon(s.kind == 'input' ? Icons.input : Icons.apps),
                      label: Text(s.title),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: client.connected
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => BrowserPage(client: client),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.language),
                label: const Text('TV’de web sayfası aç'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Sayılar ve diğer tuşlar'),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                        '0',
                      ])
                        SizedBox(
                          width: 64,
                          child: OutlinedButton(
                            onPressed: client.connected && client.pointerReady
                                ? () => key(number)
                                : null,
                            child: Text(number),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        ('Rehber', 'GUIDE'),
                        ('Bilgi', 'INFO'),
                        ('Liste', 'LIST'),
                        ('Menü', 'MENU'),
                        ('Çıkış', 'EXIT'),
                        ('Önceki kanal', 'FLASHBK'),
                        ('Altyazı', 'CC'),
                        ('Teletekst', 'TEXT'),
                        ('Kırmızı', 'RED'),
                        ('Yeşil', 'GREEN'),
                        ('Sarı', 'YELLOW'),
                        ('Mavi', 'BLUE'),
                      ])
                        OutlinedButton(
                          onPressed: client.connected && client.pointerReady
                              ? () => key(entry.$2)
                              : null,
                          child: Text(entry.$1),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Masaüstü kısayolları: yön tuşları, Enter (OK), Esc (Geri). Komut desteği TV’ye ve açık uygulamaya bağlıdır.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editShortcuts(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _ShortcutEditor(client: client),
  );
}

class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        minimumSize: const Size(48, 64),
        padding: const EdgeInsets.all(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({required this.client});
  final TVClient client;
  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late List<Shortcut> items = [...widget.client.shortcuts];
  final Map<String, TextEditingController> names = {};
  @override
  void dispose() {
    for (final c in names.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kısayolları düzenle'),
    content: SizedBox(
      width: 460,
      height: 340,
      child: ReorderableListView.builder(
        itemCount: items.length,
        onReorderItem: (a, b) => setState(() {
          items.insert(b, items.removeAt(a));
        }),
        itemBuilder: (context, index) {
          final s = items[index];
          final controller = names.putIfAbsent(
            s.id,
            () => TextEditingController(text: s.title),
          );
          return ListTile(
            key: ValueKey(s.id),
            contentPadding: const EdgeInsets.only(right: 32),
            title: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Kısayol adı'),
            ),
            leading: IconButton(
              tooltip: 'Kaldır',
              onPressed: () => setState(() => items.removeAt(index)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () async {
          final updated = items
              .map(
                (s) => Shortcut(
                  s.kind,
                  s.target,
                  names[s.id]?.text.trim() ?? s.title,
                ),
              )
              .toList();
          if (updated.any((s) => s.title.isEmpty)) return;
          await widget.client.run(
            () => widget.client.reorderShortcuts(updated),
          );
          if (context.mounted && widget.client.error == null) {
            Navigator.pop(context);
          }
        },
        child: const Text('Kaydet'),
      ),
    ],
  );
}
