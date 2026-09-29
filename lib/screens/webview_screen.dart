import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app browser used to show Privacy Policy and Support pages.
///
/// [forceLightTheme] repaints the loaded page with a strict black-on-white
/// stylesheet — used for the Privacy Policy so the legal text is always
/// legible regardless of the source styling.
///
/// [fullscreen] hides the app bar and stretches the web view to the full
/// screen with a small floating back button on top — used for Support so
/// the contact form gets as much room as possible.
///
/// When [url] is empty the screen renders a stylised "coming soon"
/// placeholder — matching the behaviour before the URLs were configured.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
    this.forceLightTheme = false,
    this.fullscreen = false,
  });

  final String title;
  final String url;
  final bool forceLightTheme;
  final bool fullscreen;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.url.trim().isNotEmpty) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(
          widget.forceLightTheme ? Colors.white : const Color(0xFF001428),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) async {
              if (widget.forceLightTheme) {
                await _injectLightTheme();
              }
              if (mounted) setState(() => _loading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    }
  }

  /// Overrides the loaded page with a strict black-on-white stylesheet.
  Future<void> _injectLightTheme() async {
    final WebViewController? c = _controller;
    if (c == null) return;
    const String js = r'''
      (function() {
        var id = 'sh-force-light';
        if (document.getElementById(id)) return;
        var s = document.createElement('style');
        s.id = id;
        s.innerHTML = "" +
          "html, body { background: #ffffff !important; color: #000000 !important; }" +
          "body, body * { color: #000000 !important; text-shadow: none !important; }" +
          "body, body *:not(a) { background-color: transparent !important; background-image: none !important; }" +
          "body { background: #ffffff !important; }" +
          "h1, h2, h3, h4, h5, h6, strong, b { color: #000000 !important; font-weight: 700 !important; }" +
          "a { color: #0033cc !important; text-decoration: underline !important; }" +
          "img, svg { filter: none !important; }" +
          "hr { border-color: #000000 !important; }";
        document.head.appendChild(s);
      })();
    ''';
    await c.runJavaScript(js);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF001428),
        appBar: _themedAppBar(context),
        body: const _EmptyStatePlaceholder(),
      );
    }
    if (widget.fullscreen) {
      return _buildFullscreen();
    }
    return _buildStandard();
  }

  PreferredSizeWidget _themedAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        widget.title,
        style: TextStyle(
          color: widget.forceLightTheme ? Colors.black : Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
      backgroundColor:
          widget.forceLightTheme ? Colors.white : const Color(0xFF001428),
      foregroundColor: widget.forceLightTheme ? Colors.black : Colors.white,
      elevation: widget.forceLightTheme ? 1 : 0,
      centerTitle: true,
      iconTheme: IconThemeData(
        color: widget.forceLightTheme ? Colors.black : Colors.white,
      ),
    );
  }

  Widget _buildStandard() {
    final Color bg =
        widget.forceLightTheme ? Colors.white : const Color(0xFF001428);
    return Scaffold(
      backgroundColor: bg,
      appBar: _themedAppBar(context),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller!),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00BFFF)),
            ),
        ],
      ),
    );
  }

  Widget _buildFullscreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      // extendBodyBehindAppBar = true is unnecessary here since we don't have
      // an app bar. The web view fills the entire scaffold.
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: WebViewWidget(controller: _controller!),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00BFFF)),
            ),
          // Floating back button — respects safe area (notch).
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _FloatingBackButton(
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.75),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _EmptyStatePlaceholder extends StatelessWidget {
  const _EmptyStatePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xAA002A55),
                border: Border.all(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.link_off_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Coming Soon',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This link is not configured yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
