import 'package:material_ui/material_ui.dart';

import '../core/android_tv/box_client.dart';
import '../core/tv_client.dart';
import '../core/protocol.dart';

/// Set up Wi-Fi control of an Android TV box (Tivibu and similar): find it, pair with the code on screen
/// and link it to the TV input it is plugged into.
class BoxSetupPage extends StatefulWidget {
  const BoxSetupPage({
    super.key,
    required this.box,
    required this.client,
    this.boxID,
    this.adding = false,
  });
  final BoxClient box;
  final TVClient client;
  final String? boxID;
  final bool adding;
  @override
  State<BoxSetupPage> createState() => _BoxSetupPageState();
}

class _BoxSetupPageState extends State<BoxSetupPage> {
  final _code = TextEditingController();
  final _host = TextEditingController();
  List<String> _found = [];
  bool _scanning = false;

  BoxClient get box => widget.box;

  @override
  void initState() {
    super.initState();
    if (widget.adding) {
      box.beginAdding();
    } else if (widget.boxID != null) {
      box.select(widget.boxID!);
    }
    if (box.box?.paired != true) _scan();
  }

  @override
  void dispose() {
    if (box.pairing != BoxPairing.done) box.cancelPairing();
    _code.dispose();
    _host.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final found = await BoxClient.scan();
      if (mounted) setState(() => _found = found);
    } catch (_) {
      // The manual address field stays available.
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String? _suggestedInput() => widget.client.inputs
      .where(
        (i) =>
            i.id.toUpperCase().startsWith('HDMI') &&
            hdmiAppID(i.id) == widget.client.foreground,
      )
      .firstOrNull
      ?.id;

  void _pair(String host) {
    _code.clear();
    box.startPairing(host, 'Android TV kutusu ($host)', _suggestedInput());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wi-Fi ile kutu kumandası')),
    body: ListenableBuilder(
      listenable: box,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: box.box?.paired == true
            ? _paired(context)
            : _pairing(context),
      ),
    ),
  );

  List<Widget> _paired(BuildContext context) {
    final current = box.box!;
    final hdmi = widget.client.inputs
        .where((i) => i.id.toUpperCase().startsWith('HDMI'))
        .toList();
    return [
      ListTile(
        title: Text(current.title(widget.client.inputs)),
        subtitle: Text(current.host),
        leading: const Icon(Icons.router_outlined),
      ),
      ListTile(
        title: const Text('Adı değiştir'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          var entered = current.customName
              ? current.name
              : current.title(widget.client.inputs);
          final name = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Kutu adı'),
              content: TextFormField(
                initialValue: entered,
                onChanged: (value) => entered = value,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, entered),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          );
          if (name != null) await box.rename(name);
        },
      ),
      SwitchListTile(
        title: const Text('Wi-Fi ile kumanda et'),
        value: box.enabled,
        onChanged: box.setEnabled,
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'TV seçilen girişteyken yön, OK, geri, ana ekran, kanal, rakam ve oynatma tuşları kutuya Wi-Fi ile gider. Ses TV’de kalır.',
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: hdmi.any((i) => i.id == current.inputID)
            ? current.inputID
            : null,
        decoration: const InputDecoration(
          labelText: 'Kutunun bağlı olduğu giriş',
        ),
        items: [
          for (final i in hdmi)
            DropdownMenuItem(value: i.id, child: Text('${i.title} · ${i.id}')),
        ],
        onChanged: box.linkInput,
      ),
      if (_suggestedInput() != null)
        TextButton(
          onPressed: () => box.linkInput(_suggestedInput()),
          child: const Text('TV’nin şu anki girişini kullan'),
        ),
      const SizedBox(height: 16),
      Text(box.status),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final (name, icon) in [
            ('UP', Icons.keyboard_arrow_up),
            ('DOWN', Icons.keyboard_arrow_down),
            ('ENTER', Icons.circle_outlined),
            ('BACK', Icons.undo),
            ('HOME', Icons.home_outlined),
          ])
            OutlinedButton(onPressed: () => box.send(name), child: Icon(icon)),
        ],
      ),
      const SizedBox(height: 24),
      TextButton(
        onPressed: () async {
          await box.forget();
          _scan();
        },
        child: const Text('Kutuyu kaldır'),
      ),
    ];
  }

  List<Widget> _pairing(BuildContext context) {
    if (box.pairing == BoxPairing.waitingForCode ||
        box.pairing == BoxPairing.verifying) {
      return [
        const Text(
          'Kutunun ekranında 6 karakterlik bir kod göründü. TV’yi kutunun girişine al ve kodu yaz.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Eşleştirme kodu',
            hintText: '37D523',
            errorText: box.pairingError,
          ),
          onSubmitted: box.finishPairing,
        ),
        FilledButton(
          onPressed: box.pairing == BoxPairing.verifying
              ? null
              : () => box.finishPairing(_code.text),
          child: Text(
            box.pairing == BoxPairing.verifying ? 'Doğrulanıyor…' : 'Eşleştir',
          ),
        ),
      ];
    }
    return [
      const Text(
        'Android TV kutusunu eşleştirirken TV’yi kutunun girişine al. Kodun göründüğü giriş kaydedilir. Kutu ile bu cihaz aynı ağda olmalı.',
      ),
      if (box.pairing == BoxPairing.failed && box.pairingError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            box.pairingError!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      if (box.pairing == BoxPairing.starting)
        const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        ),
      const SizedBox(height: 16),
      Text('Bulunan kutular', style: Theme.of(context).textTheme.titleMedium),
      if (_scanning)
        const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        ),
      for (final host in _found)
        ListTile(
          leading: const Icon(Icons.router_outlined),
          title: Text(host),
          trailing: const Text('Eşleştir'),
          onTap: box.pairing == BoxPairing.starting ? null : () => _pair(host),
        ),
      if (!_scanning && _found.isEmpty) ...[
        const Text('Kutu bulunamadı. Kutu açık ve aynı ağda mı?'),
        TextButton(onPressed: _scan, child: const Text('Yeniden ara')),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: _host,
        decoration: const InputDecoration(
          labelText: 'Kutunun IP adresi',
          hintText: '192.168.1.11',
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: box.pairing == BoxPairing.starting
            ? null
            : () {
                final host = _host.text.trim();
                if (isLocalHost(host)) {
                  _pair(host);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Geçerli bir yerel IPv4 adresi gir.'),
                    ),
                  );
                }
              },
        child: const Text('Bu adresle eşleştir'),
      ),
    ];
  }
}
