import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/player_profile.dart';
import '../widgets/themed_scaffold.dart';

/// Daily bonus screen. Displays a spinning chest, the current daily streak,
/// upcoming rewards, and a claim button (or a cool-down timer when the
/// bonus has already been claimed).
class DailyBonusScreen extends StatefulWidget {
  const DailyBonusScreen({super.key});

  @override
  State<DailyBonusScreen> createState() => _DailyBonusScreenState();
}

class _DailyBonusScreenState extends State<DailyBonusScreen>
    with TickerProviderStateMixin {
  final PlayerProfile _profile = PlayerProfile.instance;

  late final AnimationController _chestIdle;
  late final AnimationController _burst;
  Timer? _cooldownTick;
  int? _lastClaimed;

  @override
  void initState() {
    super.initState();
    _chestIdle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _profile.addListener(_onProfileChanged);
    _cooldownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cooldownTick?.cancel();
    _profile.removeListener(_onProfileChanged);
    _chestIdle.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final int reward = _profile.claimDailyBonus();
    if (reward <= 0) return;
    setState(() => _lastClaimed = reward);
    _burst.forward(from: 0);
  }

  String _formatCooldown(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool canClaim = _profile.canClaimDaily;
    final int nextReward = _profile.nextDailyReward;
    final List<int> table = _profile.dailyRewardTable;
    final int streak = _profile.dailyStreak;

    return ThemedScaffold(
      title: 'DAILY BONUS',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 6),
            Text(
              canClaim
                  ? 'Your daily gift of Fun Coins is ready.'
                  : 'Come back later for another free reward.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[_chestIdle, _burst]),
                    builder: (BuildContext context, _) {
                      final double bob =
                          math.sin(_chestIdle.value * math.pi * 2) * 4;
                      final double burst =
                          Curves.easeOutBack.transform(_burst.value);
                      return Transform.translate(
                        offset: Offset(0, -bob),
                        child: Transform.scale(
                          scale: 1 + burst * 0.15,
                          child: _Chest(canClaim: canClaim),
                        ),
                      );
                    },
                  ),
                  if (_burst.value > 0.05)
                    IgnorePointer(
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: _BurstPainter(t: _burst.value),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _RewardBigLabel(
              amount: _lastClaimed ?? nextReward,
              claimed: _lastClaimed != null,
            ),
            const SizedBox(height: 20),
            _StreakTable(table: table, currentIndex: streak),
            const SizedBox(height: 22),
            if (_lastClaimed != null)
              _PrimaryButton(
                label: 'BACK TO MENU',
                onTap: () => Navigator.of(context).pop(),
              )
            else if (canClaim)
              _PrimaryButton(
                label: 'CLAIM $nextReward',
                onTap: _claim,
                golden: true,
              )
            else
              Column(
                children: <Widget>[
                  Text(
                    'NEXT REWARD IN',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatCooldown(_profile.timeUntilNextClaim),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Chest extends StatelessWidget {
  const _Chest({required this.canClaim});
  final bool canClaim;

  @override
  Widget build(BuildContext context) {
    final Color glow = canClaim
        ? const Color(0xFFFFC107)
        : const Color(0xFF00BFFF);
    return Container(
      width: 190,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: canClaim
              ? const <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)]
              : const <Color>[Color(0xFF00E5FF), Color(0xFF003C6E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glow.withValues(alpha: 0.75),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            canClaim ? Icons.card_giftcard_rounded : Icons.lock_clock_rounded,
            size: 76,
            color: Colors.white,
            shadows: const <Shadow>[Shadow(blurRadius: 8, color: Colors.black)],
          ),
          const SizedBox(height: 4),
          Text(
            canClaim ? 'DAILY GIFT' : 'CLAIMED',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: <Shadow>[Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ],
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width * 0.5 * t;
    const int rays = 18;
    for (int i = 0; i < rays; i++) {
      final double angle = (i / rays) * math.pi * 2;
      final Offset p = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        p,
        6 * (1 - t) + 2,
        Paint()
          ..color = const Color(0xFFFFE082).withValues(alpha: 1 - t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

class _RewardBigLabel extends StatelessWidget {
  const _RewardBigLabel({required this.amount, required this.claimed});
  final int amount;
  final bool claimed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          claimed ? 'YOU RECEIVED' : 'TODAY\'S REWARD',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.stars_rounded, color: Color(0xFFFFD54F), size: 30),
            const SizedBox(width: 6),
            Text(
              '$amount',
              style: TextStyle(
                color: const Color(0xFFFFE082),
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: <Shadow>[
                  Shadow(
                    blurRadius: 20,
                    color: const Color(0xFFFFB300).withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Text(
          'FUN COINS',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

class _StreakTable extends StatelessWidget {
  const _StreakTable({required this.table, required this.currentIndex});
  final List<int> table;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '7-DAY STREAK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (int i = 0; i < table.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _StreakDay(
                      day: i + 1,
                      reward: table[i],
                      state: i < currentIndex
                          ? _DayState.claimed
                          : (i == currentIndex
                              ? _DayState.current
                              : _DayState.locked),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DayState { claimed, current, locked }

class _StreakDay extends StatelessWidget {
  const _StreakDay({
    required this.day,
    required this.reward,
    required this.state,
  });
  final int day;
  final int reward;
  final _DayState state;

  @override
  Widget build(BuildContext context) {
    final bool current = state == _DayState.current;
    final bool claimed = state == _DayState.claimed;
    final Color accent = current
        ? const Color(0xFFFFC107)
        : claimed
            ? const Color(0xFF7CFF6B)
            : Colors.white38;

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: BoxDecoration(
        color: current
            ? const Color(0x33FFC107)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.2),
        boxShadow: current
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'DAY $day',
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Icon(
            claimed ? Icons.check_circle : Icons.stars_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(height: 2),
          Text(
            '$reward',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.golden = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool golden;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: golden
                ? const <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)]
                : const <Color>[Color(0xFF00BFFF), Color(0xFF003C6E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: (golden
                      ? const Color(0xFFFFB300)
                      : const Color(0xFF00BFFF))
                  .withValues(alpha: 0.6),
              blurRadius: 22,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: golden ? const Color(0xFF3E2723) : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}
