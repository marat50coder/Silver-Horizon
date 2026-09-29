import 'package:flutter/foundation.dart';

import 'player_profile.dart';

/// Simple "missions" system. Every achievement has a target value and a
/// coin reward the player can claim once it fills up. Progress lives in
/// memory alongside [PlayerProfile].
class Achievement {
  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.reward,
  });

  final String id;
  final String title;
  final String description;
  final int target;
  final int reward;

  int _progress = 0;
  bool _claimed = false;

  int get progress => _progress.clamp(0, target);
  double get percent => target == 0 ? 1 : (_progress / target).clamp(0, 1);
  bool get completed => _progress >= target;
  bool get claimed => _claimed;
  bool get claimable => completed && !_claimed;

  void add(int amount) {
    if (_claimed) return;
    _progress = (_progress + amount).clamp(0, target);
  }

  void setTo(int value) {
    if (_claimed) return;
    if (value > _progress) _progress = value.clamp(0, target);
  }

  void markClaimed() {
    _claimed = true;
  }
}

class Achievements extends ChangeNotifier {
  Achievements._();
  static final Achievements instance = Achievements._();

  late final List<Achievement> _list = <Achievement>[
    Achievement(
      id: 'first_steps',
      title: 'First Steps',
      description: 'Spin the reels 10 times',
      target: 10,
      reward: 200,
    ),
    Achievement(
      id: 'seasoned',
      title: 'Seasoned Player',
      description: 'Spin the reels 100 times',
      target: 100,
      reward: 1500,
    ),
    Achievement(
      id: 'big_hitter',
      title: 'Big Hitter',
      description: 'Win a single spin worth x10 your bet',
      target: 1,
      reward: 500,
    ),
    Achievement(
      id: 'mega_hitter',
      title: 'Mega Hitter',
      description: 'Win a single spin worth x50 your bet',
      target: 1,
      reward: 2500,
    ),
    Achievement(
      id: 'bonus_hunter',
      title: 'Bonus Hunter',
      description: 'Trigger the bonus wheel 3 times',
      target: 3,
      reward: 1000,
    ),
    Achievement(
      id: 'mega_bonus',
      title: 'Mega Bonus',
      description: 'Trigger the bonus with 4 scatters',
      target: 1,
      reward: 2000,
    ),
    Achievement(
      id: 'hot_streak',
      title: 'Hot Streak',
      description: 'Win 5 spins in a row',
      target: 5,
      reward: 800,
    ),
    Achievement(
      id: 'daily_devotion',
      title: 'Daily Devotion',
      description: 'Claim the daily bonus 3 times',
      target: 3,
      reward: 750,
    ),
  ];

  List<Achievement> get all => List<Achievement>.unmodifiable(_list);

  int get completedCount => _list.where((Achievement a) => a.completed).length;
  int get claimableCount => _list.where((Achievement a) => a.claimable).length;

  Achievement? byId(String id) {
    for (final Achievement a in _list) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ---------- Progress hooks (called from PlayerProfile) ----------
  void onSpin(PlayerProfile p, {required int win, required int bet}) {
    byId('first_steps')?.add(1);
    byId('seasoned')?.add(1);
    if (bet > 0 && win >= bet * 10) byId('big_hitter')?.add(1);
    if (bet > 0 && win >= bet * 50) byId('mega_hitter')?.add(1);
    byId('hot_streak')?.setTo(p.longestWinStreak);
    notifyListeners();
  }

  void onBonusTriggered(PlayerProfile p, {required int scatters}) {
    byId('bonus_hunter')?.add(1);
    if (scatters >= 4) byId('mega_bonus')?.add(1);
    notifyListeners();
  }

  void onBonusWin(PlayerProfile p, {required int amount}) {
    // Bonus prizes also count as huge wins for hitter achievements.
    notifyListeners();
  }

  void onDailyClaim(PlayerProfile p) {
    byId('daily_devotion')?.add(1);
    notifyListeners();
  }

  /// Awards the reward for a completed achievement.
  bool claim(PlayerProfile p, Achievement a) {
    if (!a.claimable) return false;
    a.markClaimed();
    p.addCoins(a.reward);
    notifyListeners();
    return true;
  }
}
