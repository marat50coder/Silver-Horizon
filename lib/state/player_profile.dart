import 'package:flutter/foundation.dart';

import 'achievements.dart';

/// Singleton game state shared across every screen (menu, game, wheel,
/// paytable, daily bonus, missions, stats). Purely in-memory: state resets
/// on cold start, which is intentional for a "for fun" casino demo.
class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();
  static final PlayerProfile instance = PlayerProfile._();

  // ---------- Wallet ----------
  int _coins = 1000;
  int get coins => _coins;

  void addCoins(int amount) {
    if (amount <= 0) return;
    _coins += amount;
    notifyListeners();
  }

  bool spendCoins(int amount) {
    if (amount <= 0) return true;
    if (_coins < amount) return false;
    _coins -= amount;
    notifyListeners();
    return true;
  }

  // ---------- Session statistics ----------
  int _totalSpins = 0;
  int _paidSpins = 0;
  int _freeSpinsPlayed = 0;
  int _totalWagered = 0;
  int _totalWon = 0;
  int _biggestWin = 0;
  int _biggestMultiplier = 0;
  int _bonusRoundsTriggered = 0;
  int _winStreak = 0;
  int _longestWinStreak = 0;

  int get totalSpins => _totalSpins;
  int get paidSpins => _paidSpins;
  int get freeSpinsPlayed => _freeSpinsPlayed;
  int get totalWagered => _totalWagered;
  int get totalWon => _totalWon;
  int get biggestWin => _biggestWin;
  int get biggestMultiplier => _biggestMultiplier;
  int get bonusRoundsTriggered => _bonusRoundsTriggered;
  int get longestWinStreak => _longestWinStreak;

  /// Return-to-Player %, calculated live from wagered vs won amounts.
  double get rtp {
    if (_totalWagered == 0) return 0;
    return (_totalWon / _totalWagered) * 100;
  }

  /// Called by the game screen after each spin resolves (line wins only, the
  /// bonus wheel prize is reported via [recordBonusPrize]).
  void recordSpin({
    required int bet,
    required int win,
    required bool wasFree,
  }) {
    _totalSpins++;
    if (wasFree) {
      _freeSpinsPlayed++;
    } else {
      _paidSpins++;
      _totalWagered += bet;
    }
    if (win > 0) {
      _totalWon += win;
      if (win > _biggestWin) _biggestWin = win;
      final int mult = bet > 0 ? win ~/ bet : 0;
      if (mult > _biggestMultiplier) _biggestMultiplier = mult;
      _winStreak++;
      if (_winStreak > _longestWinStreak) _longestWinStreak = _winStreak;
    } else {
      _winStreak = 0;
    }
    Achievements.instance.onSpin(this, win: win, bet: bet);
    notifyListeners();
  }

  void recordBonusTriggered({required int scatterCount}) {
    _bonusRoundsTriggered++;
    Achievements.instance.onBonusTriggered(this, scatters: scatterCount);
    notifyListeners();
  }

  void recordBonusPrize(int amount) {
    if (amount <= 0) return;
    _totalWon += amount;
    if (amount > _biggestWin) _biggestWin = amount;
    Achievements.instance.onBonusWin(this, amount: amount);
    notifyListeners();
  }

  // ---------- Daily bonus ----------
  DateTime? _lastDailyClaim;
  int _dailyStreak = 0;
  static const List<int> _dailyRewards = <int>[
    250, 500, 750, 1000, 1500, 2000, 5000,
  ];

  int get dailyStreak => _dailyStreak;

  /// Next reward the player would receive on their next daily claim.
  int get nextDailyReward =>
      _dailyRewards[_dailyStreak.clamp(0, _dailyRewards.length - 1)];

  List<int> get dailyRewardTable => _dailyRewards;

  bool get canClaimDaily {
    if (_lastDailyClaim == null) return true;
    final Duration since = DateTime.now().difference(_lastDailyClaim!);
    return since.inHours >= 20; // slightly less than 24h so timezones are ok
  }

  /// Time remaining until the next claim becomes available.
  Duration get timeUntilNextClaim {
    if (_lastDailyClaim == null) return Duration.zero;
    final DateTime nextAt =
        _lastDailyClaim!.add(const Duration(hours: 20));
    final Duration remaining = nextAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Attempts to claim today's reward. Returns the amount awarded, or 0
  /// when the daily bonus is still on cool-down.
  int claimDailyBonus() {
    if (!canClaimDaily) return 0;
    final int reward = nextDailyReward;
    addCoins(reward);
    _lastDailyClaim = DateTime.now();
    _dailyStreak = (_dailyStreak + 1) % _dailyRewards.length;
    Achievements.instance.onDailyClaim(this);
    notifyListeners();
    return reward;
  }

  // ---------- Free spins mode ----------
  int _freeSpinsRemaining = 0;
  int _freeSpinsBet = 0;
  static const int freeSpinMultiplier = 2;

  int get freeSpinsRemaining => _freeSpinsRemaining;
  int get freeSpinsBet => _freeSpinsBet;
  bool get inFreeSpinsMode => _freeSpinsRemaining > 0;

  void grantFreeSpins({required int count, required int bet}) {
    _freeSpinsRemaining += count;
    _freeSpinsBet = bet;
    notifyListeners();
  }

  /// Called by the game screen when it starts a free-spin. Decrements the
  /// counter and returns the bet that should be considered wagered
  /// (still 0 to the player, but the reels use it for payout math).
  int consumeFreeSpin() {
    if (_freeSpinsRemaining <= 0) return 0;
    _freeSpinsRemaining--;
    if (_freeSpinsRemaining == 0) _freeSpinsBet = 0;
    notifyListeners();
    return _freeSpinsBet;
  }
}
