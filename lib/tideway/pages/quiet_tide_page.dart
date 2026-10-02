import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../infra/signal_reach.dart';

class QuietTidePage extends StatefulWidget {
  const QuietTidePage({
    super.key,
    required this.probe,
    required this.retryBuilder,
    this.probeOnMount = false,
  });

  final SignalReach probe;
  final WidgetBuilder retryBuilder;

  /// True when the page is being shown as the first Flutter frame on
  /// a cold start, before anything has verified reachability. The page
  /// then runs one silent probe and auto-advances to [retryBuilder] if
  /// it turns out we actually had a route out. Offline users never see
  /// a change — they stay on the nowifi screen that just appeared.
  final bool probeOnMount;

  @override
  State<QuietTidePage> createState() => _QuietTidePageState();
}

class _QuietTidePageState extends State<QuietTidePage> {
  bool _checking = false;
  bool _stillOffline = false;
  bool _left = false;
  bool _resumeInFlight = false;
  StreamSubscription<List<ConnectivityResult>>? _radio;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Subscribe after the first paint. connectivity_plus replays the
    // current interface on listen, and iOS often reports wifi/mobile
    // while there is still no route out. Acting on that replay inside
    // initState replaced this page with the loading splash before it
    // was ever seen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _left) return;
      _radio = widget.probe.changes.listen((states) {
        if (SignalReach.radiosUp(states)) {
          unawaited(_resumeAfterReconnect());
        }
      });
      if (widget.probeOnMount) {
        // Silent reachability check after the first paint. If the device
        // actually has a route, hand over to the loading splash without
        // waiting for the user to tap Retry. Offline users never see a
        // visible change: the probe just resolves to false and this page
        // stays exactly where it already rendered.
        unawaited(_resumeAfterReconnect());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_radio?.cancel());
    super.dispose();
  }

  Future<void> _resumeAfterReconnect() async {
    if (_left || !mounted || _resumeInFlight || _checking) return;
    _resumeInFlight = true;
    bool online = false;
    try {
      online = await widget.probe.canReachNetwork();
    } catch (_) {
      online = false;
    } finally {
      _resumeInFlight = false;
    }
    if (!online || _left || !mounted) return;
    await _enterLoading();
  }

  Future<void> _enterLoading() async {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.retryBuilder),
    );
  }

  Future<void> _retry() async {
    if (_checking || _left) return;
    HapticFeedback.lightImpact();
    setState(() {
      _checking = true;
      _stillOffline = false;
    });
    bool online = false;
    try {
      online = await widget.probe.canReachNetwork();
    } catch (_) {
      online = false;
    }
    if (!mounted) return;
    if (online) {
      await _enterLoading();
      return;
    }
    setState(() {
      _checking = false;
      _stillOffline = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.orientation == Orientation.landscape;
    final width = landscape
        ? (media.size.width * 0.40).clamp(300.0, 520.0)
        : (media.size.width * 0.66).clamp(260.0, 420.0);
    final height = landscape ? 70.0 : 74.0;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF001428),
              Color(0xFF003C6E),
              Color(0xFF001018),
            ],
            stops: <double>[0.0, 0.48, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: landscape ? 48 : 28,
              vertical: landscape ? 20 : 32,
            ),
            child: Column(
              children: <Widget>[
                const Spacer(flex: 3),
                const Text(
                  'NO INTERNET CONNECTION',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE8F7FF),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Check your connection and try again',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB0EBFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const Spacer(flex: 2),
                _RetryButton(
                  width: width,
                  height: height,
                  busy: _checking,
                  onTap: _retry,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _stillOffline
                      ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Still offline',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.width,
    required this.height,
    required this.busy,
    required this.onTap,
  });

  final double width;
  final double height;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF00BFFF), Color(0xFF005AA8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: const Color(0xFF0A2A44), width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black45,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(34),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: Color(0xFFE8F7FF),
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFFE8F7FF),
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Retry',
                          style: TextStyle(
                            color: Color(0xFFE8F7FF),
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
