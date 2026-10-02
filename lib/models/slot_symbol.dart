/// The set of symbols used on the slot reels.
///
/// Higher-tier symbols pay more but appear less frequently (lower [weight]).
enum SlotSymbol {
  // Payouts are per-bet multipliers, tuned to realistic casino RTP levels:
  // 3-of-a-kind pays a fraction to a couple of bets, 5-of-a-kind of the
  // highest symbol pays ~50–100× bet. Wilds/bars have no line payout of
  // their own — they only substitute for other symbols to complete a line.
  cherry(
    'assets/Silver_Horizon_gameplay_assets/cherry_slot_asset.webp',
    weight: 22,
    pay: <int, int>{3: 1, 4: 3, 5: 8},
  ),
  grape(
    'assets/Silver_Horizon_gameplay_assets/grape_slot_asset.webp',
    weight: 20,
    pay: <int, int>{3: 1, 4: 4, 5: 10},
  ),
  watermelon(
    'assets/Silver_Horizon_gameplay_assets/watermelon_slot_asset.webp',
    weight: 18,
    pay: <int, int>{3: 2, 4: 5, 5: 14},
  ),
  clever(
    'assets/Silver_Horizon_gameplay_assets/clever_slot_asset.webp',
    weight: 15,
    pay: <int, int>{3: 2, 4: 6, 5: 18},
  ),
  bell(
    'assets/Silver_Horizon_gameplay_assets/bell_slot_asset.webp',
    weight: 13,
    pay: <int, int>{3: 3, 4: 8, 5: 25},
  ),
  bar(
    'assets/Silver_Horizon_gameplay_assets/bar_slot_asset.webp',
    weight: 11,
    pay: <int, int>{},
  ),
  star(
    'assets/Silver_Horizon_gameplay_assets/star_slot_asset.webp',
    weight: 9,
    pay: <int, int>{3: 4, 4: 12, 5: 35},
  ),
  diamond(
    'assets/Silver_Horizon_gameplay_assets/diamond_slot_asset.webp',
    weight: 7,
    pay: <int, int>{3: 5, 4: 18, 5: 50},
  ),
  crown(
    'assets/Silver_Horizon_gameplay_assets/crown_slot_asset.webp',
    weight: 5,
    pay: <int, int>{3: 8, 4: 25, 5: 80},
  ),
  wild(
    'assets/Silver_Horizon_gameplay_assets/wild_slot_asset.webp',
    weight: 4,
    pay: <int, int>{},
  ),
  scatter(
    'assets/Silver_Horizon_gameplay_assets/Scatter_slot_asset.webp',
    weight: 3,
    pay: <int, int>{},
  );

  const SlotSymbol(
    this.assetPath, {
    required this.weight,
    required Map<int, int> pay,
  }) : _payTable = pay;

  final String assetPath;
  final int weight;
  final Map<int, int> _payTable;

  /// Payout multiplier for a run of [count] consecutive symbols from the left.
  int payout(int count) => _payTable[count] ?? 0;

  /// Wild substitutes: both the classic WILD tile *and* the BAR tile can
  /// stand in for any other paying symbol to complete a line.
  bool get isWild => this == SlotSymbol.wild || this == SlotSymbol.bar;

  bool get isScatter => this == SlotSymbol.scatter;
}
