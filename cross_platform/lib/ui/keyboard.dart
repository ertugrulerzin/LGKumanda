import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../core/android_tv/box_client.dart';
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

  /// Where typing goes: null is the TV, otherwise a paired box ID.
  /// Until chosen it follows the TV: a box input in front selects that box.
  String? _chosen;
  bool _userChose = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  SavedBox? _target(BoxClient? boxes) {
    if (boxes == null) return null;
    final id = _userChose
        ? _chosen
        : boxes.boxForForeground(widget.client.foreground)?.id;
    return boxes.pairedBoxes.where((b) => b.id == id).firstOrNull;
  }

  Future<void> send(SavedBox? target) async {
    if (sending || text.text.isEmpty) return;
    final draft = text.text;
    if (target != null) {
      final boxes = BoxClient.shared!;
      boxes.select(target.id);
      final sent = boxes.sendText(draft);
      setState(() {
        if (sent) text.clear();
        result = sent
            ? 'Metin ${target.title(widget.client.inputs)} kutusuna gönderildi. Kutuda bir arama veya metin alanı açık olmalı.'
            : 'Kutuya gönderilemedi. Kutu ayarlarından eşleştirmeyi kontrol et.';
      });
      return;
    }
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

  void _boxKey(SavedBox target, int code) {
    final boxes = BoxClient.shared!;
    boxes.select(target.id);
    boxes.sendCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final boxes = BoxClient.shared;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.client, ?boxes]),
      builder: (context, _) => _page(context, boxes),
    );
  }

  Widget _page(BuildContext context, BoxClient? boxes) {
    final client = widget.client;
    final target = _target(boxes);
    final name = target?.title(client.inputs) ?? 'TV';
    final enabled = target != null || (client.connected && !client.isHDMI);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            if (boxes != null && boxes.pairedBoxes.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Text(
                      'Yazılacak yer:',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const ValueKey('keyboardTarget.tv'),
                      avatar: const Icon(Icons.tv),
                      label: const Text('TV'),
                      selected: target == null,
                      onSelected: (_) => setState(() {
                        _userChose = true;
                        _chosen = null;
                        result = null;
                      }),
                    ),
                    for (final item in boxes.pairedBoxes)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          key: ValueKey('keyboardTarget.${item.id}'),
                          avatar: const Icon(Icons.router_outlined),
                          label: Text(item.title(client.inputs)),
                          selected: target?.id == item.id,
                          onSelected: (_) => setState(() {
                            _userChose = true;
                            _chosen = item.id;
                            result = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  if (target == null) ...[
                    if (client.isHDMI)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'TV bir HDMI girişinde. Kutuya yazmak için yukarıdan kutuyu seç.',
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
                  ] else ...[
                    Text(
                      'Yazdıkların $name kutusundaki seçili metin alanına gider. Önce kutuda arama veya metin alanını yön tuşlarıyla seç.',
                    ),
                    const SizedBox(height: 16),
                    _BoxPad(onKey: (code) => _boxKey(target, code)),
                  ],
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
                          onSubmitted: (_) => send(target),
                          decoration: InputDecoration(
                            labelText: 'Yaz → $name',
                            hintText: 'Aranacak metin…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Metni gönder',
                        onPressed: enabled && !sending
                            ? () => send(target)
                            : null,
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
                        onPressed: !enabled
                            ? null
                            : target != null
                            ? () => _boxKey(target, 66)
                            : () => client.run(() async {
                                await client.request(
                                  'com.webos.service.ime/sendEnterKey',
                                );
                              }),
                        icon: const Icon(Icons.keyboard_return),
                        label: const Text('Enter'),
                      ),
                      TextButton.icon(
                        onPressed: !enabled
                            ? null
                            : target != null
                            ? () => _boxKey(target, 67)
                            : () => client.run(() async {
                                await client.request(
                                  'com.webos.service.ime/deleteCharacters',
                                  {'count': 1},
                                );
                              }),
                        icon: const Icon(Icons.backspace_outlined),
                        label: const Text('Son karakteri sil'),
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

/// Arrows and OK for picking a text field on the box before typing.
class _BoxPad extends StatelessWidget {
  const _BoxPad({required this.onKey});
  final void Function(int code) onKey;
  @override
  Widget build(BuildContext context) {
    Widget key(IconData icon, String label, int code) => IconButton.filledTonal(
      tooltip: label,
      iconSize: 28,
      onPressed: () => onKey(code),
      icon: Icon(icon),
    );
    return Column(
      children: [
        key(Icons.keyboard_arrow_up, 'Yukarı', 19),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(Icons.keyboard_arrow_left, 'Sol', 21),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Tamam',
              iconSize: 28,
              onPressed: () => onKey(23),
              icon: const Icon(Icons.circle_outlined),
            ),
            const SizedBox(width: 8),
            key(Icons.keyboard_arrow_right, 'Sağ', 22),
          ],
        ),
        key(Icons.keyboard_arrow_down, 'Aşağı', 20),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => onKey(4),
          icon: const Icon(Icons.undo),
          label: const Text('Geri'),
        ),
      ],
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
