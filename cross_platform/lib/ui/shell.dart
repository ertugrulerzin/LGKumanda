import 'package:material_ui/material_ui.dart';

import '../core/protocol.dart';
import '../core/android_tv/box_client.dart';
import '../core/tv_client.dart';
import 'devices.dart';
import 'remote.dart';
import 'library.dart';
import 'keyboard.dart';

const destinations = [
  (Icons.settings_remote_outlined, Icons.settings_remote, 'Kumanda'),
  (Icons.apps_outlined, Icons.apps, 'Uygulamalar'),
  (Icons.live_tv_outlined, Icons.live_tv, 'Kanallar'),
  (Icons.keyboard_outlined, Icons.keyboard, 'Klavye'),
  (Icons.devices_outlined, Icons.devices, 'Cihazlar'),
];

class RemoteShell extends StatefulWidget {
  const RemoteShell({super.key, required this.client});
  final TVClient client;
  @override
  State<RemoteShell> createState() => _RemoteShellState();
}

class _RemoteShellState extends State<RemoteShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      widget.client.disconnect();
      BoxClient.shared?.disconnect();
    }
    if (state == AppLifecycleState.resumed &&
        widget.client.selected != null &&
        !widget.client.connected) {
      widget.client.connect(widget.client.selected!);
    }
  }

  int index = 0;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final client = widget.client;
        final wide = constraints.maxWidth >= 840;
        final page = switch (index) {
          0 => RemotePage(
            client: client,
            openDevices: () => setState(() => index = 4),
          ),
          1 => LibraryPage(key: const ValueKey('apps'), client: client),
          2 => LibraryPage(
            key: const ValueKey('channels'),
            client: client,
            channels: true,
          ),
          3 => KeyboardPage(client: client),
          _ => DevicesPage(client: client),
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(destinations[index].$3),
            actions: [
              if (client.state == LinkState.connecting ||
                  client.state == LinkState.pairing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (client.state != LinkState.disconnected)
                IconButton(
                  tooltip: 'Bağlantıyı kes',
                  onPressed: client.disconnect,
                  icon: const Icon(Icons.link_off),
                ),
              if (client.selected != null &&
                  client.state == LinkState.disconnected)
                TextButton.icon(
                  onPressed: () => client.connect(client.selected!),
                  icon: const Icon(Icons.link),
                  label: const Text('Bağlan'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (i) => setState(() => index = i),
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: d.$3,
                      ),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: index,
                    extended: constraints.maxWidth >= 1100,
                    onDestinationSelected: (i) => setState(() => index = i),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.$1),
                          selectedIcon: Icon(d.$2),
                          label: Text(d.$3),
                        ),
                    ],
                  ),
                if (wide) const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              client.connected ? Icons.wifi : Icons.wifi_off,
                              size: 18,
                              color: client.connected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${client.selected?.name ?? 'TV seçilmedi'} · ${client.connectionLabel}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (client.error != null || client.notice != null)
                        MaterialBanner(
                          content: Text(client.error ?? client.notice!),
                          leading: Icon(
                            client.error != null
                                ? Icons.error_outline
                                : Icons.info_outline,
                          ),
                          actions: [
                            TextButton(
                              onPressed: client.clearMessages,
                              child: const Text('Kapat'),
                            ),
                          ],
                        ),
                      Expanded(child: page),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 24), child: action!),
          ],
        ),
      ),
    ),
  );
}
