import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/protocol.dart';
import '../core/tv_client.dart';
import 'keyboard.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.client});
  final TVClient client;
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final address = TextEditingController();
  InAppWebViewController? controller;
  WebViewEnvironment? environment;
  Uri? initial;
  String? failure, lastSent;
  bool sending = false, webViewReady = !Platform.isWindows;
  double progress = 0;
  Timer? mirrorTimer;
  Directory? temporaryData;
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) unawaited(_prepareWindows());
  }

  Future<void> _prepareWindows() async {
    try {
      if (await WebViewEnvironment.getAvailableVersion() == null) {
        throw StateError('WebView2 Runtime gerekiyor.');
      }
      temporaryData = await Directory.systemTemp.createTemp('lgkumanda-web-');
      final env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: temporaryData!.path,
        ),
      );
      if (!mounted) {
        await env.dispose();
        return;
      }
      setState(() {
        environment = env;
        webViewReady = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => failure = 'Tarayıcı açılamadı. Windows için Microsoft Edge WebView2 Runtime kurulu olmalı. TV’ye adres göndermeyi kullanabilirsin.',
        );
      }
    }
  }

  @override
  void dispose() {
    address.dispose();
    mirrorTimer?.cancel();
    // WebView2 owns this temporary directory until its native view has closed.
    if (environment != null) unawaited(environment!.dispose());
    super.dispose();
  }

  Future<void> open() async {
    if (sending) return;
    setState(() {
      sending = true;
      failure = null;
    });
    try {
      final target = browserTarget(address.text);
      await widget.client.openBrowser(target);
      if (!mounted) return;
      lastSent = target.toString();
      if (controller != null) {
        await controller!.loadUrl(
          urlRequest: URLRequest(url: WebUri.uri(target)),
        );
      } else {
        setState(() => initial = target);
      }
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        setState(() => failure = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void mirror(WebUri? url) {
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.userInfo.isNotEmpty ||
        url.toString() == lastSent) {
      return;
    }
    mirrorTimer?.cancel();
    mirrorTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await widget.client.openBrowser(Uri.parse(url.toString()));
        if (mounted) {
          setState(() {
            lastSent = url.toString();
            address.text = lastSent!;
            failure = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => failure = 'Sayfa TV’de açılamadı. TV bağlantısını kontrol et ve adresi yeniden gönder.',
          );
        }
      }
    });
  }

  Future<void> touchPad() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AnimatedBuilder(
        animation: widget.client,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'TV’de dokunmatik',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'TV’deki oynat düğmesini veya doğrulama kutusunu hedefle ve tıkla. Telefonda yapılan doğrulama TV’ye aktarılmaz.',
              ),
              const SizedBox(height: 16),
              TouchPad(client: widget.client, forceMouse: true),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('TV’de web'),
        actions: [
          IconButton(
            tooltip: 'TV’de dokunmatik',
            onPressed: widget.client.pointerReady ? touchPad : null,
            icon: const Icon(Icons.mouse_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: address,
                          keyboardType: TextInputType.webSearch,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => open(),
                          decoration: const InputDecoration(
                            labelText: 'Adres veya Google araması',
                            hintText: 'example.com',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'TV’de aç',
                        onPressed: sending || !widget.client.connected
                            ? null
                            : open,
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
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        failure!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (initial == null)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    Text(
                      'Bağlantıyı burada seç, TV’de aç',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sayfa hem bu cihazda hem TV’de açılır. Burada dokunduğun bağlantılar TV’ye adres olarak gönderilir. Ekran yansıtma yapılmaz; oturumlar ve sayfa içi tıklamalar paylaşılmaz.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Video oynatma ve güvenlik doğrulamaları için TV’de dokunmatik panelini kullan. Videonun çalışması sitenin TV tarayıcısıyla uyumuna bağlıdır. AirPlay kullanılmaz.',
                    ),
                    const Divider(height: 32),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Deneysel işaretçisiz web gezinmesi'),
                      subtitle: const Text(
                        'Kumandanın yön tuşları sayfadaki öğeleri işaretler. Son Claude oturumundan taşınmıştır; her sitede ve iframe oynatıcısında doğrulanmamıştır.',
                      ),
                      value: widget.client.webFocusEnabled,
                      onChanged: widget.client.setWebFocus,
                    ),
                  ],
                ),
              )
            else ...[
              if (progress < 1) LinearProgressIndicator(value: progress),
              Expanded(
                child: !webViewReady
                    ? const Center(child: Text('Yerel tarayıcı hazırlanıyor…'))
                    : InAppWebView(
                        webViewEnvironment: environment,
                        initialUrlRequest: URLRequest(
                          url: WebUri.uri(initial!),
                        ),
                        initialSettings: InAppWebViewSettings(
                          incognito: true,
                          useShouldOverrideUrlLoading: true,
                          javaScriptCanOpenWindowsAutomatically: false,
                          supportMultipleWindows: false,
                          mediaPlaybackRequiresUserGesture: true,
                        ),
                        initialUserScripts: UnmodifiableListView([
                          UserScript(
                            source: """
            document.addEventListener('play', function(e) {
              if (e.target && e.target.pause) { e.target.pause(); e.target.muted = true; }
              if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('tvMedia');
            }, true);
          """,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_START,
                            forMainFrameOnly: false,
                          ),
                        ]),
                        onWebViewCreated: (c) {
                          controller = c;
                          c.addJavaScriptHandler(
                            handlerName: 'tvMedia',
                            callback: (_) {
                              unawaited(touchPad());
                              return null;
                            },
                          );
                        },
                        shouldOverrideUrlLoading: (_, action) async =>
                            [
                                  'http',
                                  'https',
                                ].contains(action.request.url?.scheme) &&
                                (action.request.url?.userInfo.isEmpty ?? true)
                            ? NavigationActionPolicy.ALLOW
                            : NavigationActionPolicy.CANCEL,
                        onLoadStart: (_, url) => mirror(url),
                        onUpdateVisitedHistory: (_, url, _) => mirror(url),
                        onProgressChanged: (_, value) {
                          if (mounted) setState(() => progress = value / 100);
                        },
                        onReceivedError: (_, request, _) {
                          if (request.isForMainFrame == true && mounted) {
                            setState(
                              () => failure = 'Sayfa bu cihazda yüklenemedi. Adresi ve internet bağlantını kontrol et.',
                            );
                          }
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Bu cihazda geri',
                      onPressed: () => controller?.goBack(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    IconButton(
                      tooltip: 'Bu cihazda ileri',
                      onPressed: () => controller?.goForward(),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    IconButton(
                      tooltip: 'TV sayfasını yukarı kaydır',
                      onPressed: widget.client.pointerReady
                          ? () =>
                                widget.client.run(() => widget.client.key('UP'))
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'TV sayfasını aşağı kaydır',
                      onPressed: widget.client.pointerReady
                          ? () => widget.client.run(
                              () => widget.client.key('DOWN'),
                            )
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    TextButton.icon(
                      onPressed: widget.client.pointerReady ? touchPad : null,
                      icon: const Icon(Icons.mouse_outlined),
                      label: const Text('TV’de dokunmatik'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
