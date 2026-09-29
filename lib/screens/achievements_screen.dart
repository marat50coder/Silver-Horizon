import 'package:flutter/material.dart';

import '../state/achievements.dart';
import '../state/player_profile.dart';
import '../widgets/themed_scaffold.dart';

/// Achievements / Missions screen. Lists every mission with a progress bar,
/// a lock/claim state, and a coin reward that can be collected once the
/// mission fills up.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final PlayerProfile _profile = PlayerProfile.instance;
  final Achievements _achievements = Achievements.instance;

  @override
  void initState() {
    super.initState();
    _achievements.addListener(_onChanged);
    _profile.addListener(_onChanged);
  }

  @override
  void dispose() {
    _achievements.removeListener(_onChanged);
    _profile.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _claim(Achievement a) {
    if (_achievements.claim(_profile, a)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Center(
              child: Text(
                '+${a.reward} FUN COINS',
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            backgroundColor: const Color(0xCC001A33),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1400),
            margin: const EdgeInsets.only(bottom: 120, left: 40, right: 40),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Achievement> list = _achievements.all;
    final int completed = _achievements.completedCount;
    return ThemedScaffold(
      title: 'MISSIONS',
      trailing: _CoinsPill(coins: _profile.coins),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          _SummaryRow(completed: completed, total: list.length),
          const SizedBox(height: 12),
          for (final Achievement a in list) _MissionTile(a: a, onClaim: _claim),
        ],
      ),
    );
  }
}

class _CoinsPill extends StatelessWidget {
  const _CoinsPill({required this.coins});
  final int coins;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xAA001A33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.75),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.stars_rounded, color: Color(0xFFFFD54F), size: 14),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.completed, required this.total});
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final double pct = total == 0 ? 0 : completed / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.emoji_events_rounded,
                  color: Color(0xFFFFD54F), size: 20),
              const SizedBox(width: 8),
              Text(
                '$completed / $total COMPLETED',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFC107),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.a, required this.onClaim});
  final Achievement a;
  final void Function(Achievement) onClaim;

  @override
  Widget build(BuildContext context) {
    final bool claimable = a.claimable;
    final bool claimed = a.claimed;
    final Color accent = claimable
        ? const Color(0xFFFFC107)
        : claimed
            ? const Color(0xFF7CFF6B)
            : const Color(0xFF00BFFF);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: tileDecoration(tint: accent),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.35),
              border: Border.all(color: accent, width: 1.4),
            ),
            child: Icon(
              claimed
                  ? Icons.check_rounded
                  : (claimable
                      ? Icons.card_giftcard_rounded
                      : Icons.emoji_events_rounded),
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  a.title.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    shadows: <Shadow>[
                      Shadow(
                        blurRadius: 8,
                        color: accent.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: a.percent,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${a.progress}/${a.target}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RewardBadge(a: a, onClaim: onClaim),
        ],
      ),
    );
  }
}

class _RewardBadge extends StatelessWidget {
  const _RewardBadge({required this.a, required this.onClaim});
  final Achievement a;
  final void Function(Achievement) onClaim;

  @override
  Widget build(BuildContext context) {
    if (a.claimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Text(
          'DONE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      );
    }
    if (a.claimable) {
      return GestureDetector(
        onTap: () => onClaim(a),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.7),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              const Text(
                'CLAIM',
                style: TextStyle(
                  color: Color(0xFF3E2723),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '+${a.reward}',
                style: const TextStyle(
                  color: Color(0xFF3E2723),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'REWARD',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          Text(
            '+${a.reward}',
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
