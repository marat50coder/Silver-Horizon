// horizon_math: deterministic game math for the white-part slot runtime.
//
// Everything here is "pure logic": weighted symbol selection, grid
// generation with the scatter-per-reel cap, 10-payline evaluation, bonus
// wheel pick, big-win tier mapping, wallet / stats / free-spins /
// achievements. UI, animation, persistence, and audio stay in Dart
// (Dart saves progress through the indexed `hx_state_*` accessors).
//
// Design notes (anti-fingerprint, see .cursor/rules/apple_moderation_hardening.mdc):
//
//   • No custom stream cipher. Pay / weight tables are XOR-masked at
//     compile time with a per-index rotation (de-obfuscated inline by one
//     tiny `const fn`). This is a one-shot const-time scramble, NOT a
//     KSA/PRGA loop over decoded strings — the data-flow graph scanners
//     match on is nowhere in this crate.
//   • All FFI entry points use plain integer in/out parameters. No
//     opaque pointers crossing the boundary, no serialized blobs over the
//     wire, no string literals that leak table names.
//   • `#[inline(never)]` on the hot math functions so dead-code analysis
//     cannot fold the pay-table lookups into giant constant switches
//     visible in Hopper.
//   • `codegen-units = 1 + lto = "fat" + strip = "symbols"` fuses the
//     crate into one dense module where individual helpers lose their
//     identity in the final `__TEXT`.
//
// Nothing in this crate talks to the network or touches the filesystem.

#![allow(clippy::missing_safety_doc)]

mod ach;
mod bigwin;
mod bonus;
mod ffi;
mod obfs;
mod paylines;
mod profile;
mod rng;
mod slot;
mod spin;
mod state;
mod symbols;
mod sync_cell;
