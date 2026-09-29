import 'package:flutter/material.dart';

import '../state/player_profile.dart';
import '../widgets/app_layout.dart';
import 'achievements_screen.dart';
import 'daily_bonus_screen.dart';
import 'game_screen.dart';
import 'paytable_screen.dart';
import 'statistics_screen.dart';
import 'webview_screen.dart';

/// Root menu shown after the loading screen. Central PLAY button, secondary
/// grid of feature entry points (Paytable / Daily / Missions / Stats), and
/// the standard Privacy / Support links at the bottom.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final PlayerProfile _profile = PlayerProfile.instance;

  @override
  void initState() {
    super.initState();
    _profile.addListener(_onChanged);
  }

  @override
  void dispose() {
    _profile.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  static const String _privacyUrl =
      'https://silverhorrizon.com/privacy-policy.html';
  static const String _supportUrl =
      'https://silverhorrizon.com/support.html';

  void _openWebView(
    String title,
    String url, {
    bool forceLightTheme = false,
    bool fullscreen = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebViewScreen(
          title: title,
          url: url,
          forceLightTheme: forceLightTheme,
          fullscreen: fullscreen,
        ),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dailyReady = _profile.canClaimDaily;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/Silver_Horizon_additional_assets/Vertical_Loading_Screen.webp',
            fit: BoxFit.cover,
            // On iPad the aspect is closer to square, so anchor the crop at
            // the top so the SILVER HORIZON logo baked into the artwork stays
            // fully visible instead of being cut off.
            alignment: AppLayout.isTablet(context)
                ? Alignment.topCenter
                : Alignment.center,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x66000000),
                  Color(0xB3000000),
                ],
                stops: <double>[0.0, 0.55, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          SafeArea(
            child: AppLayout.constrained(
              context: context,
              maxWidth: AppLayout.menuMaxWidth(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        _CoinsHeaderBadge(coins: _profile.coins),
                      ],
                    ),
                  const Spacer(flex: 5),
                  const _FunCoinsBadge(),
                  const SizedBox(height: 18),
                  _MenuButton(
                    label: 'PLAY',
                    primary: true,
                    icon: Icons.play_arrow_rounded,
                    onTap: () => _push(const GameScreen()),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SquareTile(
                          label: 'DAILY',
                          icon: Icons.card_giftcard_rounded,
                          badge: dailyReady ? 'READY' : null,
                          golden: dailyReady,
                          onTap: () => _push(const DailyBonusScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SquareTile(
                          label: 'MISSIONS',
                          icon: Icons.emoji_events_rounded,
                          onTap: () => _push(const AchievementsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SquareTile(
                          label: 'PAYTABLE',
                          icon: Icons.grid_view_rounded,
                          onTap: () => _push(const PaytableScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SquareTile(
                          label: 'STATS',
                          icon: Icons.bar_chart_rounded,
                          onTap: () => _push(const StatisticsScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SmallButton(
                          label: 'PRIVACY',
                          icon: Icons.privacy_tip_outlined,
                          onTap: () => _openWebView(
                            'Privacy Policy',
                            _privacyUrl,
                            forceLightTheme: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SmallButton(
                          label: 'SUPPORT',
                          icon: Icons.support_agent_outlined,
                          onTap: () => _openWebView(
                            'Support',
                            _supportUrl,
                            fullscreen: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                    const Spacer(flex: 1),
                    const _DisclaimerFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinsHeaderBadge extends StatelessWidget {
  const _CoinsHeaderBadge({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xAA001A33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFD54F).withValues(alpha: 0.9),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFC107).withValues(alpha: 0.4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.stars_rounded, color: Color(0xFFFFD54F), size: 18),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FunCoinsBadge extends StatelessWidget {
  const _FunCoinsBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x99001A33),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFFFD54F).withValues(alpha: 0.9),
          width: 1.4,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFC107).withValues(alpha: 0.35),
            blurRadius: 14,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.stars_rounded, color: Color(0xFFFFD54F), size: 20),
          SizedBox(width: 8),
          Text(
            'FUN COINS  •  NOT REAL MONEY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerFooter extends StatelessWidget {
  const _DisclaimerFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          'NO REAL MONEY. ONLY FUN.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            shadows: <Shadow>[
              Shadow(
                blurRadius: 10,
                color: const Color(0xFF00BFFF).withValues(alpha: 0.8),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This game is intended for adult entertainment purposes only.\n'
          'It does not offer real-money gambling or any opportunity to win real money or prizes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) => _press.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (BuildContext context, Widget? child) {
          final double scale = 1 - _press.value * 0.05;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          height: widget.primary ? 62 : 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.primary
                  ? const <Color>[Color(0xFF00E5FF), Color(0xFF003C6E)]
                  : const <Color>[Color(0xAA002A55), Color(0xAA001428)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: widget.primary
                  ? Colors.white
                  : const Color(0xFF00BFFF).withValues(alpha: 0.85),
              width: widget.primary ? 2 : 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF00BFFF)
                    .withValues(alpha: widget.primary ? 0.7 : 0.45),
                blurRadius: widget.primary ? 22 : 14,
                spreadRadius: widget.primary ? 2 : 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                widget.icon,
                color: Colors.white,
                size: widget.primary ? 26 : 22,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.primary ? 20 : 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: widget.primary ? 5 : 4,
                  shadows: <Shadow>[
                    Shadow(
                      blurRadius: 10,
                      color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareTile extends StatelessWidget {
  const _SquareTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
    this.golden = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final bool golden;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 82,
        // Fixed height + full width from Expanded ensures every tile is
        // the exact same size regardless of label length.
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: golden
                      ? const <Color>[Color(0xAA5D3A00), Color(0xAA1A1000)]
                      : const <Color>[Color(0xAA002A55), Color(0xAA001428)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: golden
                      ? const Color(0xFFFFC107)
                      : const Color(0xFF00BFFF).withValues(alpha: 0.75),
                  width: 1.4,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: (golden
                            ? const Color(0xFFFFC107)
                            : const Color(0xFF00BFFF))
                        .withValues(alpha: 0.45),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icon,
                      color: golden ? const Color(0xFFFFE082) : Colors.white,
                      size: 26,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFFC107).withValues(alpha: 0.7),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Color(0xFF3E2723),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xAA001A33),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFF00BFFF).withValues(alpha: 0.75),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
