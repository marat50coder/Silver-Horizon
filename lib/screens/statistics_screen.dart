import 'package:flutter/material.dart';

import '../state/achievements.dart';
import '../state/player_profile.dart';
import '../widgets/themed_scaffold.dart';

/// Session statistics screen — spins, coins wagered/won, RTP, biggest hit,
/// longest streak, bonus rounds, missions progress.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final PlayerProfile p = _profile;
    return ThemedScaffold(
      title: 'STATISTICS',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          _BalanceCard(coins: p.coins),
          const SizedBox(height: 14),
          _SectionLabel('SPINS'),
          const SizedBox(height: 6),
          _StatGrid(items: <_Stat>[
            _Stat('Total spins', '${p.totalSpins}', Icons.refresh_rounded),
            _Stat('Paid spins', '${p.paidSpins}', Icons.paid_rounded),
            _Stat('Free spins', '${p.freeSpinsPlayed}',
                Icons.card_giftcard_rounded),
            _Stat('Bonus rounds', '${p.bonusRoundsTriggered}',
                Icons.emoji_events_rounded),
          ]),
          const SizedBox(height: 14),
          _SectionLabel('COINS'),
          const SizedBox(height: 6),
          _StatGrid(items: <_Stat>[
            _Stat('Total wagered', '${p.totalWagered}',
                Icons.arrow_upward_rounded),
            _Stat('Total won', '${p.totalWon}', Icons.arrow_downward_rounded),
            _Stat(
              'RTP',
              p.totalWagered == 0 ? '—' : '${p.rtp.toStringAsFixed(1)}%',
              Icons.percent_rounded,
            ),
            _Stat(
              'Net',
              p.totalWagered == 0
                  ? '0'
                  : (p.totalWon - p.totalWagered).toString(),
              Icons.savings_rounded,
            ),
          ]),
          const SizedBox(height: 14),
          _SectionLabel('BEST'),
          const SizedBox(height: 6),
          _StatGrid(items: <_Stat>[
            _Stat('Biggest win', '${p.biggestWin}',
                Icons.local_fire_department_rounded),
            _Stat('Biggest multiplier',
                p.biggestMultiplier == 0 ? '—' : 'x${p.biggestMultiplier}',
                Icons.flash_on_rounded),
            _Stat('Longest streak', '${p.longestWinStreak}',
                Icons.trending_up_rounded),
            _Stat('Missions', '${Achievements.instance.completedCount}',
                Icons.check_circle_rounded),
          ]),
          const SizedBox(height: 20),
          _Disclaimer(),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: tileDecoration(tint: const Color(0xFFFFC107)),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.7),
                  blurRadius: 16,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.stars_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'CURRENT BALANCE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              Text(
                '$coins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                'FUN COINS  •  NOT REAL MONEY',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});
  final List<_Stat> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double gap = 10;
        final double tileWidth = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final _Stat s in items)
              SizedBox(width: tileWidth, child: _StatCard(stat: s)),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: tileDecoration(),
      child: Row(
        children: <Widget>[
          Icon(stat.icon, color: const Color(0xFF00E5FF), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stat.label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
          shadows: <Shadow>[
            Shadow(
              blurRadius: 10,
              color: const Color(0xFF00BFFF).withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Stats reset when the app is closed. Golden Crown is for entertainment '
      'only — no real money is wagered or won.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        height: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
