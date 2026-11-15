import 'package:material_ui/material_ui.dart';

import '../core/storage.dart';
import '../core/tv_client.dart';
import 'shell.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.client, this.channels = false});
  final TVClient client;
  final bool channels;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String query = '';
  bool inputs = false;
  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (!client.connected) {
      return const EmptyState(
        icon: Icons.link_off,
        title: 'Önce TV’ye bağlan',
        message: 'Kayıtlı TV’ne bağlandıktan sonra uygulamalar, girişler ve kanallar burada görünür.',
      );
    }
    final kind = widget.channels
        ? 'channel'
        : inputs
        ? 'input'
        : 'app';
    final source = widget.channels
        ? client.channels
        : inputs
        ? client.inputs
        : client.apps;
    final items = source
        .where(
          (e) => '${e.title} ${e.detail}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  if (!widget.channels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Uygulamalar'),
                            icon: Icon(Icons.apps),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('HDMI / Girişler'),
                            icon: Icon(Icons.input),
                          ),
                        ],
                        selected: {inputs},
                        onSelectionChanged: (s) => setState(() {
                          inputs = s.first;
                          query = '';
                        }),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey(kind),
                          onChanged: (s) => setState(() => query = s),
                          decoration: InputDecoration(
                            labelText: widget.channels
                                ? 'Kanal ara'
                                : 'Listede ara',
                            prefixIcon: const Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Listeleri yenile',
                        onPressed: client.loadingLibrary
                            ? null
                            : client.refreshLibrary,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (client.loadingLibrary) const LinearProgressIndicator(),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: client.loadingLibrary
                          ? 'TV listesi okunuyor'
                          : 'Gösterilecek öğe yok',
                      message: query.isEmpty
                          ? 'Bu TV listeyi desteklemeyebilir. Yenile ile tekrar deneyebilirsin.'
                          : 'Başka bir ad veya kanal numarası dene.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final shortcut = Shortcut(kind, item.id, item.title);
                        final pinned = client.shortcuts.any(
                          (s) => s.id == shortcut.id,
                        );
                        return ListTile(
                          leading: Icon(
                            inputs
                                ? Icons.input
                                : widget.channels
                                ? Icons.live_tv
                                : Icons.apps,
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            inputs
                                ? '${item.id} · ${item.simplink ?? 'SIMPLINK cihazı yok'}'
                                : item.detail.isEmpty
                                ? item.id
                                : item.detail,
                          ),
                          onTap: () =>
                              client.run(() => client.activate(kind, item.id)),
                          trailing: widget.channels
                              ? null
                              : IconButton(
                                  tooltip: pinned
                                      ? 'Kısayoldan kaldır'
                                      : 'Kumandaya sabitle',
                                  onPressed: () => client.run(
                                    () => client.pin(shortcut, remove: pinned),
                                  ),
                                  icon: Icon(
                                    pinned ? Icons.star : Icons.star_border,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
