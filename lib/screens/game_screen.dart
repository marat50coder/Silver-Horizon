import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/player_profile.dart';
import '../widgets/app_layout.dart';
import '../widgets/bet_selector.dart';
import '../widgets/big_win_overlay.dart';
import '../widgets/slot_machine.dart';
import '../widgets/spin_button.dart';
import '../widgets/win_popup.dart';
import 'bonus_wheel_screen.dart';

/// The main portrait-only slot game screen.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver {
  static const List<int> _betOptions = <int>[1, 5, 10, 25, 50, 100];

  final GlobalKey<SlotMachineState> _slotKey = GlobalKey<SlotMachineState>();
  final PlayerProfile _profile = PlayerProfile.instance;

  int _lastWin = 0;
  int _lastLineCount = 0;
  int _betIndex = 0;
  bool _spinning = false;
  bool _showWinPopup = false;

  int? _bigWinAmount;
  int? _bigWinMultiplier;

  int get _bet => _betOptions[_betIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockPortrait();
    _profile.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    _profile.removeListener(_onProfileChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lockPortrait();
  }

  void _lockPortrait() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  }

  void _selectBet(int index) {
    if (_spinning) return;
    setState(() => _betIndex = index);
  }

  Future<void> _spin() async {
    if (_spinning) return;

    final bool isFreeSpin = _profile.inFreeSpinsMode;
    final int betForSpin =
        isFreeSpin ? _profile.freeSpinsBet : _bet;

    if (!isFreeSpin && !_profile.spendCoins(_bet)) {
      _showMessage('Not enough fun coins');
      return;
    }
    if (isFreeSpin) {
      _profile.consumeFreeSpin();
    }

    _slotKey.currentState?.clearHighlights();

    setState(() {
      _spinning = true;
      _lastWin = 0;
      _lastLineCount = 0;
      _showWinPopup = false;
      _bigWinAmount = null;
      _bigWinMultiplier = null;
    });

    final SpinResult result =
        await _slotKey.currentState!.spin(bet: betForSpin);

    if (!mounted) return;

    // Free spins double the line win.
    final int rawWin = result.lineWin;
    final int payout = isFreeSpin
        ? rawWin * PlayerProfile.freeSpinMultiplier
        : rawWin;

    _profile.addCoins(payout);
    _profile.recordSpin(bet: betForSpin, win: payout, wasFree: isFreeSpin);

    setState(() {
      _spinning = false;
      _lastWin = payout;
      _lastLineCount = _slotKey.currentState?.winCount ?? 0;
      if (payout > 0) _showWinPopup = true;
    });

    // Trigger Big Win overlay for large multipliers.
    if (payout > 0 && betForSpin > 0) {
      final int mult = payout ~/ betForSpin;
      if (BigWinOverlay.tierFor(mult) != null) {
        setState(() {
          _bigWinAmount = payout;
          _bigWinMultiplier = mult;
          _showWinPopup = false;
        });
      }
    }

    // Bonus round: on scatter trigger.
    if (result.scatterCount >= 3) {
      _profile.recordBonusTriggered(scatterCount: result.scatterCount);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      final BonusResult? bonus = await Navigator.of(context).push<BonusResult>(
        PageRouteBuilder<BonusResult>(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.6),
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, _, _) => BonusWheelScreen(
            bet: betForSpin,
            scatterCount: result.scatterCount,
          ),
          transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
            return FadeTransition(opacity: anim, child: child);
          },
        ),
      );
      if (!mounted || bonus == null) return;

      if (bonus.coins > 0) {
        _profile.addCoins(bonus.coins);
        _profile.recordBonusPrize(bonus.coins);
        setState(() {
          _lastWin += bonus.coins;
          _showWinPopup = true;
        });
        // Extremely large bonus prizes also deserve the Big Win overlay.
        final int mult = betForSpin > 0 ? bonus.coins ~/ betForSpin : 0;
        if (BigWinOverlay.tierFor(mult) != null) {
          setState(() {
            _bigWinAmount = bonus.coins;
            _bigWinMultiplier = mult;
            _showWinPopup = false;
          });
        }
      }
      if (bonus.freeSpins > 0) {
        _profile.grantFreeSpins(count: bonus.freeSpins, bet: betForSpin);
        _showMessage('${bonus.freeSpins} FREE SPINS AWARDED');
      }
    }
  }

  void _dismissWinPopup() {
    if (!mounted) return;
    setState(() => _showWinPopup = false);
    _slotKey.currentState?.clearHighlights();
  }

  void _dismissBigWin() {
    if (!mounted) return;
    setState(() {
      _bigWinAmount = null;
      _bigWinMultiplier = null;
      if (_lastWin > 0) _showWinPopup = true;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          backgroundColor: const Color(0xCC001A33),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
          margin: const EdgeInsets.only(bottom: 200, left: 40, right: 40),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool freeMode = _profile.inFreeSpinsMode;
    final int coins = _profile.coins;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/Silver_Horizon_gameplay_assets/background_game.webp',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withValues(alpha: 0.25)),
          // Golden overlay while in free-spin mode.
          if (freeMode)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[
                      const Color(0xFFFFC107).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: AppLayout.constrained(
              context: context,
              maxWidth: AppLayout.gameMaxWidth(context),
              child: Column(
              children: <Widget>[
                _TopBar(
                  coins: coins,
                  freeSpinsLeft: _profile.freeSpinsRemaining,
                  onHomeTap: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: math.min(size.width * 0.03, 16),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          SlotMachine(key: _slotKey),
                          if (_showWinPopup &&
                              _lastWin > 0 &&
                              _bigWinAmount == null)
                            WinPopup(
                              key: ValueKey<int>(_lastWin),
                              amount: _lastWin,
                              lineCount: _lastLineCount,
                              onDone: _dismissWinPopup,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StatusRow(
                    win: _lastWin,
                    bet: freeMode ? _profile.freeSpinsBet : _bet,
                    lineCount: _lastLineCount,
                    freeMode: freeMode,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BetSelector(
                    options: _betOptions,
                    selectedIndex: _betIndex,
                    onSelected: freeMode ? (_) {} : _selectBet,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 18),
                  child: SpinButton(
                    onTap: _spin,
                    disabled: _spinning || (!freeMode && coins < _bet),
                  ),
                ),
              ],
            ),
            ),
          ),

          if (_bigWinAmount != null && _bigWinMultiplier != null)
            BigWinOverlay(
              amount: _bigWinAmount!,
              multiplier: _bigWinMultiplier!,
              onDone: _dismissBigWin,
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.coins,
    required this.freeSpinsLeft,
    required this.onHomeTap,
  });
  final int coins;
  final int freeSpinsLeft;
  final VoidCallback onHomeTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _GlassIconButton(icon: Icons.home_rounded, onTap: onHomeTap),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/Silver_Horizon_additional_assets/Game_name.webp',
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CoinsBadge(coins: coins),
            ],
          ),
          const SizedBox(height: 2),
          if (freeSpinsLeft > 0)
            _FreeSpinsBanner(count: freeSpinsLeft)
          else
            const Text(
              'FUN COINS  •  NO REAL MONEY',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
        ],
      ),
    );
  }
}

class _FreeSpinsBanner extends StatelessWidget {
  const _FreeSpinsBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.7),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(
        'FREE SPINS  •  x${PlayerProfile.freeSpinMultiplier}  •  $count LEFT',
        style: const TextStyle(
          color: Color(0xFF3E2723),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xAA001A33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00BFFF).withValues(alpha: 0.75),
              width: 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF00BFFF).withValues(alpha: 0.35),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _CoinsBadge extends StatelessWidget {
  const _CoinsBadge({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xAA001A33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.75),
          width: 1.4,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF00BFFF).withValues(alpha: 0.35),
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
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.win,
    required this.bet,
    required this.lineCount,
    required this.freeMode,
  });
  final int win;
  final int bet;
  final int lineCount;
  final bool freeMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> anim) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        );
      },
      child: Container(
        key: ValueKey<int>(win),
        height: 34,
        alignment: Alignment.center,
        child: win > 0
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'WIN  ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: <Shadow>[
                        Shadow(
                          blurRadius: 12,
                          color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$win',
                    style: TextStyle(
                      color: const Color(0xFFFFE082),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: <Shadow>[
                        Shadow(
                          blurRadius: 18,
                          color: const Color(0xFFFFB300).withValues(alpha: 0.95),
                        ),
                      ],
                    ),
                  ),
                  if (lineCount > 1) ...<Widget>[
                    const SizedBox(width: 10),
                    Text(
                      '($lineCount lines)',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    freeMode ? 'FREE ' : 'BET ',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    '$bet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '•  10 LINES',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
