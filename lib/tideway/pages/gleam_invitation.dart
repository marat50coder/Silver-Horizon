import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/gleam_horizon_config.dart';
import '../infra/horizon_beacon.dart';
import '../infra/horizon_vault.dart';

class GleamInvitation extends StatefulWidget {
  const GleamInvitation({
    super.key,
    required this.vault,
    required this.notifications,
    required this.nextBuilder,
    this.onTokenReady,
  });

  final HorizonVault vault;
  final HorizonBeacon notifications;
  final WidgetBuilder nextBuilder;
  final Future<void> Function(String token)? onTokenReady;

  @override
  State<GleamInvitation> createState() => _GleamInvitationState();
}

class _GleamInvitationState extends State<GleamInvitation> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _accept() async {
    if (_working) return;
    setState(() => _working = true);
    final granted = await widget.notifications.askPermission();
    // The APNs token resolves in the background now — we deliberately do
    // NOT block the "Accept" tap on `_waitForApns` + `getToken` because
    // those add 3–6 s of spinner time after the user already granted
    // permission. If a caller still wants the token (via onTokenReady),
    // forward whatever is cached without blocking the handoff; the
    // coordinator picks the token up asynchronously via onTokenChanged.
    final token = widget.notifications.token;
    if (granted && token != null && token.isNotEmpty) {
      unawaited(widget.onTokenReady?.call(token) ?? Future<void>.value());
    }
    if (!granted) await _snooze();
    _continue();
  }

  Future<void> _skip() async {
    if (_working) return;
    setState(() => _working = true);
    await _snooze();
    _continue();
  }

  Future<void> _snooze() {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        GleamHorizonConfig.pushSnoozeSeconds;
    return widget.vault.snoozePushInvite(until);
  }

  void _continue() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.nextBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.orientation == Orientation.landscape;
    final background = landscape
        ? 'assets/Silver_Horizon_additional_assets/'
              'sh_permit_landscape.webp'
        : 'assets/Silver_Horizon_additional_assets/'
              'sh_permit_portrait.webp';
    // Base sizes shrunk 25% (user request) and narrowed to 60% of the
    // original width (20% in on each side), with both buttons identical.
    final baseWidth = landscape
        ? (media.size.width * 0.42).clamp(320.0, 560.0)
        : (media.size.width * 0.80).clamp(280.0, 440.0);
    final width = baseWidth * 0.60 * 0.75 * 2;
    final height = (landscape ? 66.0 : 74.0) * 0.75;
    final fontSize = (landscape ? 22.0 : 25.0) * 0.80;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            background,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
          Align(
            alignment: Alignment(0, landscape ? 0.80 : 0.90),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _InviteButton(
                  width: width,
                  height: height,
                  fontSize: fontSize,
                  label: 'Accept',
                  emphasized: true,
                  busy: _working,
                  onTap: _accept,
                ),
                SizedBox(height: landscape ? 10 : 12),
                _InviteButton(
                  width: width,
                  height: height,
                  fontSize: fontSize,
                  label: 'Skip',
                  emphasized: false,
                  busy: false,
                  onTap: _skip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({
    required this.width,
    required this.height,
    required this.fontSize,
    required this.label,
    required this.emphasized,
    required this.busy,
    required this.onTap,
  });

  final double width;
  final double height;
  final double fontSize;
  final String label;
  final bool emphasized;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            colors: emphasized
                ? const <Color>[Color(0xFF00BFFF), Color(0xFF005AA8)]
                : const <Color>[Color(0xFF7EC8E3), Color(0xFF1A4A6E)],
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
            borderRadius: BorderRadius.circular(radius),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Color(0xFFE8F7FF),
                      ),
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFE8F7FF),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
