import 'package:material_ui/material_ui.dart';

import '../core/discovery.dart';
import '../core/android_tv/box_client.dart';
import 'box_setup.dart';
import '../core/protocol.dart';
import '../core/tv_client.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.client});
  final TVClient client;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final discovery = TVDiscovery();
  @override
  void dispose() {
    discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: discovery,
    builder: (context, _) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (BoxClient.shared case final box?)
              ListenableBuilder(
                listenable: box,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Android TV kutuları',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final saved in box.boxes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.router_outlined),
                        title: Text(saved.title(widget.client.inputs)),
                        subtitle: Text(
                          '${saved.host} · ${saved.paired ? "Eşleşti" : "Eşleştirme gerekli"}',
                        ),
                        trailing: const Icon(Icons.settings_outlined),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BoxSetupPage(
                              box: box,
                              client: widget.client,
                              boxID: saved.id,
                            ),
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BoxSetupPage(
                            box: box,
                            client: widget.client,
                            adding: true,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Android TV kutusu ekle'),
                    ),
                    const Divider(height: 32),
                  ],
                ),
              ),
            Text(
              'TV’ni bağla',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'TV ve bu cihaz aynı yerel ağda olmalı. İlk bağlantıda TV ekranındaki eşleştirme isteğini kabul et.',
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => editDevice(context, widget.client),
                  icon: const Icon(Icons.add),
                  label: const Text('TV ekle'),
                ),
                OutlinedButton.icon(
                  onPressed: discovery.searching
                      ? discovery.cancel
                      : () => discovery.search(
                          widget.client.televisions.map((t) => t.host).toList(),
                        ),
                  icon: Icon(discovery.searching ? Icons.stop : Icons.search),
                  label: Text(
                    discovery.searching ? 'Aramayı durdur' : 'Ağda LG TV ara',
                  ),
                ),
              ],
            ),
            if (discovery.searching) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: discovery.total == 0
                    ? null
                    : discovery.checked / discovery.total,
              ),
              const SizedBox(height: 8),
              Text(
                '${discovery.checked} / ${discovery.total} adres kontrol edildi',
              ),
            ],
            if (discovery.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(discovery.message!),
              ),
            if (discovery.found.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Ağda bulunanlar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final tv in discovery.found)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tv),
                  title: Text(tv.name),
                  subtitle: Text(tv.host),
                  trailing: TextButton(
                    onPressed: () async {
                      final saved = await widget.client.savedForDiscovered(tv, discovery.fingerprints[tv.host]);
                      if (!context.mounted) return;
                      if (saved != null) { await widget.client.connect(saved); }
                      else { await editDevice(context, widget.client, tv); }
                    },
                    child: const Text('Bağlan'),
                  ),
                ),
            ],
            const SizedBox(height: 28),
            Text(
              'Kayıtlı televizyonlar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.client.televisions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Henüz TV eklenmedi. Ağda ara veya TV’nin ağ ayarlarındaki IP adresini kullan.',
                ),
              ),
            for (final tv in widget.client.televisions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.client.connected &&
                          widget.client.selected?.host == tv.host
                      ? Icons.tv
                      : Icons.tv_outlined,
                ),
                title: Text(tv.name),
                subtitle: Text(
                  '${tv.host} · ${tv.secure ? 'Şifreli WSS' : 'Şifresiz WS'}',
                ),
                onTap: () => widget.client.connect(tv),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Cihaz seçenekleri',
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await editDevice(context, widget.client, tv);
                    }
                    if (action == 'remove' && context.mounted) {
                      final confirmed = await confirm(
                        context,
                        'TV kaydı silinsin mi?',
                        'Eşleştirme anahtarı ve bu TV’nin kısayolları da silinir.',
                      );
                      if (confirmed) {
                        await widget.client.run(
                          () => widget.client.removeTV(tv),
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    PopupMenuItem(value: 'remove', child: Text('Sil')),
                  ],
                ),
              ),
            if (widget.client.selected != null) ...[
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: () => widget.client.run(widget.client.wake),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Seçili TV’yi uyandır'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Yeniden eşleştirilsin mi?',
                    'TV’yi doğruladığından emin ol. Kayıtlı anahtar ve sertifika silinip yeniden onay istenecek.',
                  )) {
                    await widget.client.run(widget.client.resetPairing);
                  }
                },
                child: const Text('Seçili TV ile yeniden eşleştir'),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Wake-on-LAN için MAC adresini ve gerekirse yerel yayın adresini cihaz ayarlarından gir. TV’nin ağ üzerinden açılma ayarı da açık olmalı.',
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> editDevice(
  BuildContext context,
  TVClient client, [
  Television? tv,
]) async {
  final result = await showDialog<Television>(
    context: context,
    builder: (_) => _DeviceEditor(tv: tv),
  );
  if (result != null) {
    await client.run(() async {
      await client.saveTV(result);
      await client.connect(result);
    });
  }
}

class _DeviceEditor extends StatefulWidget {
  const _DeviceEditor({this.tv});
  final Television? tv;
  @override
  State<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends State<_DeviceEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.tv?.name ?? 'Salon TV');
  late final host = TextEditingController(text: widget.tv?.host ?? '');
  late final mac = TextEditingController(text: widget.tv?.mac ?? '');
  late final broadcast = TextEditingController(
    text: widget.tv?.broadcast ?? '255.255.255.255',
  );
  late bool secure = widget.tv?.secure ?? true;
  @override
  void dispose() {
    for (final c in [name, host, mac, broadcast]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Televizyon'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'TV adı'),
                validator: (v) => v!.trim().isEmpty ? 'Bir ad gir.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: host,
                readOnly: widget.tv != null && widget.tv!.host.isNotEmpty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Yerel IPv4 adresi',
                  hintText: '192.168.1.50',
                ),
                validator: (v) => isLocalHost(v!.trim())
                    ? null
                    : 'Geçerli bir yerel IPv4 adresi gir.',
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Şifreli bağlantı (WSS)'),
                value: secure,
                onChanged: (v) => setState(() => secure = v),
              ),
              if (!secure)
                const Text(
                  'WS bağlantısında komutlar ve eşleştirme anahtarı ağda şifrelenmeden taşınır. Yalnızca eski TV gerekiyorsa kullan.',
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: mac,
                decoration: const InputDecoration(
                  labelText: 'MAC adresi (isteğe bağlı)',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
                validator: (v) {
                  if (v!.trim().isEmpty) return null;
                  try {
                    magicPacket(v.trim());
                    return null;
                  } catch (_) {
                    return 'Geçerli bir MAC adresi gir.';
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: broadcast,
                decoration: const InputDecoration(
                  labelText: 'Uyandırma yayın adresi',
                ),
                validator: (v) =>
                    v == '255.255.255.255' || isLocalHost(v!.trim())
                    ? null
                    : 'Geçerli bir yerel yayın adresi gir.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              Television(
                id: widget.tv?.storageID,
                deviceUUID: widget.tv?.deviceUUID,
                host: host.text.trim(),
                name: name.text.trim(),
                secure: secure,
                mac: mac.text.trim(),
                broadcast: broadcast.text.trim(),
              ),
            );
          }
        },
        child: const Text('Kaydet ve bağlan'),
      ),
    ],
  );
}
