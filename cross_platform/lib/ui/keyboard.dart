import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../core/tv_client.dart';
import 'browser.dart';

class KeyboardPage extends StatefulWidget {
  const KeyboardPage({super.key, required this.client});
  final TVClient client;
  @override
  State<KeyboardPage> createState() => _KeyboardPageState();
}

class _KeyboardPageState extends State<KeyboardPage> {
  final text = TextEditingController();
  bool sending = false;
  String? result;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || text.text.isEmpty) return;
    final draft = text.text;
    setState(() {
      sending = true;
      result = null;
    });
    await widget.client.run(() async {
      await widget.client.request('com.webos.service.ime/insertText', {
        'text': draft,
        'replace': 0,
      });
      if (mounted) {
        if (text.text == draft) text.clear();
        setState(() => result = 'Metin TV’ye gönderildi.');
      }
    });
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final enabled = client.connected && !client.isHDMI;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  if (client.isHDMI)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'HDMI kutusunda işaretçisiz yön/OK kullanılır. TV klavyesi ve fare imleci kutuya aktarılmaz.',
                      ),
                    ),
                  TouchPad(client: client),
                  const SizedBox(height: 20),
                  const Text(
                    'Yazmadan önce TV’de arama veya metin alanını seç. Gönderim başarısız olursa yazdıkların korunur.',
                  ),
                  const SizedBox(height: 16),
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
                    label: const Text('Web adresi veya Google araması'),
                  ),
                ],
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(result!),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: text,
                          enabled: enabled && !sending,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'TV’ye yaz',
                            hintText: 'Aranacak metin…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Metni TV’ye gönder',
                        onPressed: enabled && !sending ? send : null,
                        icon: sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    children: [
                      TextButton.icon(
                        onPressed: enabled
                            ? () => client.run(() async {
                                await client.request(
                                  'com.webos.service.ime/sendEnterKey',
                                );
                              })
                            : null,
                        icon: const Icon(Icons.keyboard_return),
                        label: const Text('TV Enter'),
                      ),
                      TextButton.icon(
                        onPressed: enabled
                            ? () => client.run(() async {
                                await client.request(
                                  'com.webos.service.ime/deleteCharacters',
                                  {'count': 1},
                                );
                              })
                            : null,
                        icon: const Icon(Icons.backspace_outlined),
                        label: const Text('TV’de son karakteri sil'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TouchPad extends StatefulWidget {
  const TouchPad({super.key, required this.client, this.forceMouse = false});
  final TVClient client;
  final bool forceMouse;
  @override
  State<TouchPad> createState() => _TouchPadState();
}

class _TouchPadState extends State<TouchPad> {
  bool mouse = false, quiet = true;
  double sensitivity = .8;
  Offset total = Offset.zero, remainder = Offset.zero;
  bool get mouseMode => !widget.client.isHDMI && (widget.forceMouse || mouse);
  bool get enabled => widget.client.connected && widget.client.pointerReady;
  void action(VoidCallback action) => widget.client.run(() async {
    action();
  });
  void move(Offset delta) {
    if (!enabled) return;
    total += delta;
    if (!mouseMode || (quiet && !widget.forceMouse)) return;
    final value = delta * sensitivity + remainder;
    final dx = value.dx.clamp(-32, 32).truncate(),
        dy = value.dy.clamp(-32, 32).truncate();
    remainder = Offset(value.dx - dx, value.dy - dy);
    widget.client.move(dx, dy);
  }

  void end() {
    if (!enabled) return;
    if (mouseMode) {
      if (quiet && !widget.forceMouse) {
        action(
          () => widget.client.jump(
            (total.dx * sensitivity).round(),
            (total.dy * sensitivity).round(),
          ),
        );
      }
    } else if (total.distance > 20) {
      final key = total.dx.abs() > total.dy.abs()
          ? (total.dx > 0 ? 'RIGHT' : 'LEFT')
          : (total.dy > 0 ? 'DOWN' : 'UP');
      widget.client.run(() => widget.client.key(key));
    }
    total = Offset.zero;
    remainder = Offset.zero;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (!widget.forceMouse && !widget.client.isHDMI) ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.open_with),
              label: Text('İşaretçisiz'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.mouse_outlined),
              label: Text('Fare'),
            ),
          ],
          selected: {mouse},
          onSelectionChanged: (s) => setState(() => mouse = s.first),
        ),
        const SizedBox(height: 16),
      ],
      Semantics(
        label: mouseMode
            ? 'TV fare alanı. Sürükle ve dokunarak tıkla.'
            : 'İşaretçisiz yön alanı. Kaydır ve OK için dokun.',
        enabled: enabled,
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && enabled && mouseMode) {
              action(
                () => widget.client.pointer(
                  'type:scroll\ndx:0\ndy:${event.scrollDelta.dy.sign.toInt()}\n\n',
                ),
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !enabled
                ? null
                : () {
                    if (mouseMode) {
                      action(() => widget.client.pointer('type:click\n\n'));
                    } else {
                      widget.client.run(() => widget.client.key('ENTER'));
                    }
                  },
            onPanStart: !enabled
                ? null
                : (_) {
                    total = Offset.zero;
                    remainder = Offset.zero;
                  },
            onPanUpdate: !enabled ? null : (details) => move(details.delta),
            onPanEnd: !enabled ? null : (_) => end(),
            onPanCancel: () {
              total = Offset.zero;
              remainder = Offset.zero;
            },
            child: Container(
              height: 220,
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mouseMode ? Icons.mouse_outlined : Icons.open_with,
                    size: 36,
                    color: enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    mouseMode
                        ? 'Sürükle · dokunarak tıkla'
                        : 'Kaydır · dokunarak OK',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    enabled
                        ? (mouseMode
                              ? 'TV işaretçisini kontrol et'
                              : 'İmleci hareket ettirmeden gezin')
                        : 'TV ve işaretçi bağlantısı gerekiyor',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (mouseMode) ...[
        if (!widget.forceMouse)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sessiz fare'),
            subtitle: const Text(
              'Hareketi parmağını kaldırınca tek seferde gönderir.',
            ),
            value: quiet,
            onChanged: (v) => setState(() => quiet = v),
          ),
        Row(
          children: [
            const Text('Hassasiyet'),
            Expanded(
              child: Slider(
                value: sensitivity,
                min: .2,
                max: 2,
                divisions: 18,
                label: sensitivity.toStringAsFixed(1),
                onChanged: (v) => setState(() => sensitivity = v),
              ),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              (Icons.arrow_left, -4, 0, 'İşaretçiyi sola kaydır'),
              (Icons.arrow_upward, 0, -4, 'İşaretçiyi yukarı kaydır'),
              (Icons.arrow_downward, 0, 4, 'İşaretçiyi aşağı kaydır'),
              (Icons.arrow_right, 4, 0, 'İşaretçiyi sağa kaydır'),
            ])
              IconButton.outlined(
                tooltip: item.$4,
                onPressed: enabled
                    ? () => action(() => widget.client.jump(item.$2, item.$3))
                    : null,
                icon: Icon(item.$1),
              ),
            FilledButton(
              onPressed: enabled
                  ? () => action(() => widget.client.pointer('type:click\n\n'))
                  : null,
              child: const Text('Tıkla'),
            ),
          ],
        ),
      ],
    ],
  );
}
