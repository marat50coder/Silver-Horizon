import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../infra/gleam_route_reader.dart';
import '../infra/horizon_agent.dart';
import '../infra/horizon_beacon.dart';
import '../infra/horizon_vault.dart';
import '../infra/signal_reach.dart';
import 'quiet_tide_page.dart';

class HorizonPortal extends StatefulWidget {
  const HorizonPortal({
    super.key,
    required this.url,
    required this.vault,
    required this.probe,
    required this.notifications,
    required this.agent,
    this.coldLaunch = false,
  });

  final String url;
  final HorizonVault vault;
  final SignalReach probe;
  final HorizonBeacon notifications;
  final HorizonAgent agent;
  final bool coldLaunch;

  @override
  State<HorizonPortal> createState() => _HorizonPortalState();
}

class _HorizonPortalState extends State<HorizonPortal>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  bool _viewportReady = false;
  bool _coldReloadIssued = false;
  bool _offlineShown = false;
  int _redirectAttempts = 0;
  String? _lastMainUrl;
  Timer? _metricsDebounce;
  Timer? _pageFinishTimer;
  Size? _lastMetricsSize;
  bool _holdColdReload = false;
  // Keeps the branded splash visible under the WebView until the first
  // page finishes painting. The default WKWebView background is black
  // (we must keep it that way so the WebView itself does not flash
  // white between navigations), so without this overlay the user sees
  // a 1–3 s black rectangle while HTTPS + first paint complete.
  bool _firstPaintDone = false;
  // Safety net: hide the splash even if the page never fires
  // onPageFinished (slow network, blocked resources). Mirrors the
  // LoadingScreen hard deadline for the portal handoff.
  Timer? _splashHideFloor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    final params = Platform.isIOS
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    _controller =
        WebViewController.fromPlatformCreationParams(
            params,
            onPermissionRequest: (request) => request.grant(),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setUserAgent(widget.agent.userAgent)
          ..enableZoom(false)
          ..setNavigationDelegate(_navigation());
    if (_controller.platform is WebKitWebViewController) {
      (_controller.platform as WebKitWebViewController)
          .setAllowsBackForwardNavigationGestures(true);
    }

    widget.notifications.onDestination = _openPushUrl;
    _networkSubscription = widget.probe.changes.listen((states) {
      if (states.every((state) => state == ConnectivityResult.none)) {
        // Verify with a real DNS probe before tearing down the WebView.
        // connectivity_plus flips to `none` during cold start, radio
        // switches (wifi↔cellular) and screen-wake transitions even
        // when the network is fully usable — a direct `_goOffline()`
        // here was flashing a phantom no-wifi page over the gray
        // content when a user clicked the OneLink and the OS was
        // mid-handshake.
        _showOfflineAfterProbe();
      }
    });

    if (widget.coldLaunch) {
      _settleColdViewport();
    } else {
      _viewportReady = true;
      _controller.loadRequest(Uri.parse(widget.url));
    }
    // Hard floor for the splash overlay — even if onPageFinished never
    // fires (long-running XHR, blocked tracker, etc.), the user should
    // not stare at the loading splash forever. 8 s matches the longest
    // acceptable first-paint budget observed on 3G in testing.
    _splashHideFloor = Timer(const Duration(seconds: 8), () {
      if (!mounted || _firstPaintDone) return;
      setState(() => _firstPaintDone = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _settleColdViewport() async {
    _enterImmersive();
    // Short settle so the viewport metrics stabilise before the first
    // paint — long enough for one frame + immersive animation, short
    // enough that the splash overlay (above the WebView) does not sit
    // on top of a visibly stalled surface.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() => _viewportReady = true);
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    setState(() {});
    final view = View.of(context);
    final size = view.physicalSize;
    final rotated = _lastMetricsSize != null &&
        ((_lastMetricsSize!.width < _lastMetricsSize!.height) !=
            (size.width < size.height));
    _lastMetricsSize = size;
    if (!rotated) return;
    _enterImmersive();
    _metricsDebounce?.cancel();
    _pokeReflow(const <int>[55, 190, 380, 610, 920]);
  }

  void _pokeReflow(List<int> delaysMs) {
    for (final ms in delaysMs) {
      Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _controller
            .runJavaScript(
              'window.dispatchEvent(new Event("orientationchange"));'
              'window.dispatchEvent(new Event("resize"));'
              'if(window.visualViewport)'
              '  window.visualViewport.dispatchEvent(new Event("resize"));',
            )
            .catchError((_) {});
      });
    }
    _metricsDebounce = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      _installShell();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterImmersive();
      _consumePending();
    }
  }

  void _openPushUrl(String url) {
    final uri = Uri.tryParse(url);
    if (!mounted || uri == null || !uri.hasScheme) return;
    _holdColdReload = true;
    _pageFinishTimer?.cancel();
    _controller.loadRequest(uri);
  }

  Future<void> _consumePending() async {
    final stored = await widget.vault.consumePushUrl();
    final fromScene = await GleamRouteReader.consume();
    final value = (fromScene != null && fromScene.isNotEmpty)
        ? fromScene
        : stored;
    if (value != null && value.isNotEmpty) {
      _openPushUrl(value);
    }
  }

  NavigationDelegate _navigation() {
    return NavigationDelegate(
      onPageStarted: (url) {
        _lastMainUrl = url;
      },
      onPageFinished: (_) {
        _redirectAttempts = 0;
        _installShell();
        // Hide the splash overlay as soon as the first page paints —
        // for cold-start pushes we WAIT for the second paint (after
        // the reload) so the user never sees the reload flash.
        if (!_firstPaintDone) {
          final needsReload = widget.coldLaunch &&
              !_coldReloadIssued &&
              !_holdColdReload;
          if (!needsReload) {
            setState(() => _firstPaintDone = true);
          }
        }
        _pageFinishTimer?.cancel();
        _pageFinishTimer = Timer(const Duration(milliseconds: 640), () async {
          if (!mounted) return;
          setState(() {});
          await _controller.runJavaScript(
            'window.dispatchEvent(new Event("resize"));'
            'window.visualViewport?.dispatchEvent(new Event("resize"));',
          );
          _installShell();
          if (widget.coldLaunch &&
              !_coldReloadIssued &&
              !_holdColdReload) {
            _coldReloadIssued = true;
            await _controller.reload();
          } else if (!_firstPaintDone && mounted) {
            // Second-paint path after cold reload: drop the splash.
            setState(() => _firstPaintDone = true);
          }
        });
      },
      onWebResourceError: (error) {
        if (error.errorCode == -999) return;
        final mainFrame = error.isForMainFrame ?? true;
        final lower = error.description.toLowerCase();
        final redirectLoop = error.errorCode == -1007 ||
            lower.contains('too_many_redirects') ||
            lower.contains('too many redirects');
        if (redirectLoop && _lastMainUrl != null && _redirectAttempts < 4) {
          _redirectAttempts++;
          _controller.loadRequest(Uri.parse(_lastMainUrl!));
          return;
        }
        if (!mainFrame) return;
        _showOfflineAfterProbe();
      },
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        if (<String>{
          'http',
          'https',
          'about',
          'data',
          'blob',
        }.contains(uri.scheme)) {
          if (request.isMainFrame) _lastMainUrl = request.url;
          return NavigationDecision.navigate;
        }
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return NavigationDecision.prevent;
      },
    );
  }

  Future<void> _showOfflineAfterProbe() async {
    if (_offlineShown) return;
    bool online = true;
    try {
      // Mirror the splash preflight: on a true cold start / wake the
      // first DNS resolver call can take 1–2 s even on a strong link,
      // so give it the same budget here instead of a single short
      // probe that would misfire as "offline" and flash QuietTidePage.
      online = await widget.probe.canReachNetwork(
        perHostTimeout: const Duration(milliseconds: 1800),
        attempts: 2,
        retryDelay: const Duration(milliseconds: 500),
      );
    } catch (_) {
      online = false;
    }
    if (online) return;
    _goOffline();
  }

  Future<void> _goOffline() async {
    if (_offlineShown || !mounted) return;
    _offlineShown = true;
    String current;
    try {
      current = await _controller.currentUrl() ?? widget.url;
    } catch (_) {
      current = widget.url;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuietTidePage(
          probe: widget.probe,
          retryBuilder: (_) => HorizonPortal(
            url: current,
            vault: widget.vault,
            probe: widget.probe,
            notifications: widget.notifications,
            agent: widget.agent,
          ),
        ),
      ),
    );
  }

  void _installShell() {
    _controller.runJavaScript(r'''
(() => {
  const root = window;
  if (root.__hzShell) {
    root.__hzShellRefresh && root.__hzShellRefresh();
    return;
  }
  root.__hzShell = true;
  const marker = 'hz-inset-sheet';
  const rules = [
    ':root{',
    '--safe-area-inset-top:0px!important;',
    '--safe-area-inset-right:0px!important;',
    '--safe-area-inset-bottom:0px!important;',
    '--safe-area-inset-left:0px!important;',
    '--sat:0px!important;--sar:0px!important;',
    '--sab:0px!important;--sal:0px!important;',
    '--safe-top:0px!important;--safe-right:0px!important;',
    '--safe-bottom:0px!important;--safe-left:0px!important;',
    '}',
    'html,body{overscroll-behavior:none!important;',
    'overscroll-behavior-y:none!important;}',
    '*{-webkit-tap-highlight-color:transparent!important;}',
    '*:not(input):not(textarea):not([contenteditable="true"]){',
    '-webkit-touch-callout:none!important;}',
    'input,textarea,select,[contenteditable="true"]{',
    'font-size:max(16px,1em)!important;}'
  ].join('');
  const keyboardVisible = () => {
    const visual = root.visualViewport;
    return !!visual && visual.height < root.innerHeight * 0.75;
  };
  const lockViewport = () => {
    const host = document.head || document.documentElement;
    if (!host) return;
    let vp = document.querySelector('meta[name="viewport"]');
    if (!vp) {
      vp = document.createElement('meta');
      vp.setAttribute('name', 'viewport');
      host.appendChild(vp);
    }
    vp.setAttribute('content',
      'width=device-width, initial-scale=1.0, maximum-scale=1.0, ' +
      'minimum-scale=1.0, user-scalable=no, viewport-fit=contain');
  };
  const refresh = () => {
    if (keyboardVisible()) return;
    const host = document.head || document.documentElement;
    if (!host) return;
    lockViewport();
    let sheet = document.getElementById(marker);
    if (!sheet) {
      sheet = document.createElement('style');
      sheet.id = marker;
      host.appendChild(sheet);
    }
    sheet.textContent = rules;
  };
  const schedule = () => {
    root.setTimeout(refresh, 190);
    root.setTimeout(refresh, 710);
  };
  const editable = (node) => !!node && (
    node.matches?.('input, textarea, select, [contenteditable="true"]')
  );
  const reveal = () => {
    const active = document.activeElement;
    if (!editable(active)) return;
    active.scrollIntoView({behavior: 'auto', block: 'nearest'});
  };
  document.addEventListener('focusin', (event) => {
    if (editable(event.target)) root.setTimeout(reveal, 410);
  }, true);
  const stop = (e) => { e.preventDefault(); };
  ['gesturestart', 'gesturechange', 'gestureend'].forEach((t) =>
    document.addEventListener(t, stop, {passive: false}));
  document.addEventListener('touchmove', (e) => {
    if (e.scale !== undefined && e.scale !== 1) e.preventDefault();
  }, {passive: false});
  let lastTap = 0;
  document.addEventListener('touchend', (e) => {
    const now = Date.now();
    if (now - lastTap <= 280) e.preventDefault();
    lastTap = now;
  }, {passive: false});
  ['pushState', 'replaceState'].forEach((name) => {
    const original = history[name];
    history[name] = function(...args) {
      const result = original.apply(this, args);
      schedule();
      return result;
    };
  });
  root.addEventListener('popstate', schedule);
  root.__hzShellRefresh = refresh;
  refresh();
  root.setInterval(refresh, 3100);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metricsDebounce?.cancel();
    _pageFinishTimer?.cancel();
    _splashHideFloor?.cancel();
    _networkSubscription?.cancel();
    widget.notifications.onDestination = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).viewPadding;
    final orientation = MediaQuery.of(context).orientation;
    final splashAsset = orientation == Orientation.portrait
        ? 'assets/Silver_Horizon_additional_assets/sh_splash_portrait.webp'
        : 'assets/Silver_Horizon_additional_assets/sh_splash_landscape.webp';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_viewportReady)
              Padding(
                padding: EdgeInsets.only(
                  top: safe.top,
                  bottom: safe.bottom,
                  left: safe.left,
                  right: safe.right,
                ),
                child: WebViewWidget(controller: _controller),
              ),
            // Branded splash sits above the WebView until the first
            // page actually paints. WKWebView's own background has to
            // stay black (so navigations do not flash white), which
            // means without this overlay the user would stare at a
            // black rectangle while the HTTPS handshake + initial
            // render complete. AnimatedOpacity gives a 220 ms fade so
            // the handoff never looks like a jump cut.
            IgnorePointer(
              ignoring: _firstPaintDone,
              child: AnimatedOpacity(
                opacity: _firstPaintDone ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.asset(splashAsset, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, 0.6),
                          radius: 1.2,
                          colors: <Color>[
                            Colors.transparent,
                            Color(0x55000000),
                          ],
                        ),
                      ),
                    ),
                    const Align(
                      alignment: Alignment(0, 0.72),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
