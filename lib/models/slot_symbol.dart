import '../math/horizon_ffi.dart' as rust;

/// The set of symbols used on the slot reels.
///
/// Every symbol owns its asset path and its stable `rustIndex` into the
/// Rust `horizon_math` static library — the index MUST match the order
/// declared in `rust/horizon_math/src/symbols.rs`. Weight and pay tables
/// no longer live on the Dart side: `payout`, `isWild`, `isScatter` all
/// call back into Rust, so there is a single source of truth for the
/// game math and nothing recognisable as "slot pay table" ships inside
/// the Dart snapshot.
enum SlotSymbol {
  cherry(0, 'assets/Silver_Horizon_gameplay_assets/cherry_slot_asset.webp'),
  grape(1, 'assets/Silver_Horizon_gameplay_assets/grape_slot_asset.webp'),
  watermelon(2,
      'assets/Silver_Horizon_gameplay_assets/watermelon_slot_asset.webp'),
  clever(3, 'assets/Silver_Horizon_gameplay_assets/clever_slot_asset.webp'),
  bell(4, 'assets/Silver_Horizon_gameplay_assets/bell_slot_asset.webp'),
  bar(5, 'assets/Silver_Horizon_gameplay_assets/bar_slot_asset.webp'),
  star(6, 'assets/Silver_Horizon_gameplay_assets/star_slot_asset.webp'),
  diamond(7, 'assets/Silver_Horizon_gameplay_assets/diamond_slot_asset.webp'),
  crown(8, 'assets/Silver_Horizon_gameplay_assets/crown_slot_asset.webp'),
  wild(9, 'assets/Silver_Horizon_gameplay_assets/wild_slot_asset.webp'),
  scatter(10, 'assets/Silver_Horizon_gameplay_assets/Scatter_slot_asset.webp');

  const SlotSymbol(this.rustIndex, this.assetPath);

  final int rustIndex;
  final String assetPath;

  /// Payout multiplier for a run of [count] consecutive symbols from the
  /// left. Delegates to the Rust pay-table (obfuscated via per-index XOR
  /// so the actual multiplier values are not readable from a strings
  /// dump of the static library).
  int payout(int count) => rust.hxSymbolPayout(rustIndex, count);

  /// Only WILD substitutes for another symbol. BAR pays on its own line.
  bool get isWild => rust.hxSymbolIsWild(rustIndex) != 0;

  bool get isScatter => rust.hxSymbolIsScatter(rustIndex) != 0;

  /// Resolves a 0..10 index — the exact representation Rust uses in its
  /// grid — back to a Dart enum value.
  static SlotSymbol fromIndex(int index) {
    if (index < 0 || index >= SlotSymbol.values.length) {
      return SlotSymbol.cherry;
    }
    return SlotSymbol.values[index];
  }
}
