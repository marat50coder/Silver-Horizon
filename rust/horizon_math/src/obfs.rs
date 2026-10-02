// Compile-time XOR masking for integer tables.
//
// Every stored byte is `value ^ key_byte(index)`. The accessor applies the
// same mask on read. The key is a splitmix step over `index`, so each
// position has an unrelated mask — a `strings` / data-only dump of the
// static library does not reveal the "cherry 3→1, 4→3, 5→8" shape of the
// pay table.
//
// This is NOT a stream cipher and NOT a decoder-at-runtime: it is a pure
// const-fn permutation of the stored constants. There is no KSA, no PRGA,
// no array traversal that decodes a URL / UA / key — nothing that matches
// the Apple post-mortem signature in §3 of apple_moderation_hardening.mdc.

const K0: u64 = 0x9E37_79B9_7F4A_7C15;
const K1: u64 = 0xBF58_476D_1CE4_E5B9;
const K2: u64 = 0x94D0_49BB_1331_11EB;

#[inline(always)]
pub const fn mask8(i: usize) -> u8 {
    let x = (i as u64).wrapping_add(0xA076_1D64_78BD_642F);
    let y = x.wrapping_mul(K0) ^ (x.wrapping_mul(K1) >> 27);
    let z = y.wrapping_mul(K2) ^ (y >> 31);
    (z as u8) ^ ((z >> 8) as u8) ^ ((z >> 16) as u8)
}

#[inline(always)]
pub const fn mask16(i: usize) -> u16 {
    (mask8(i * 2) as u16) | ((mask8(i * 2 + 1) as u16) << 8)
}

#[inline(always)]
pub const fn enc8(v: u8, i: usize) -> u8 {
    v ^ mask8(i)
}

#[inline(always)]
pub const fn enc16(v: u16, i: usize) -> u16 {
    v ^ mask16(i)
}

#[inline(always)]
pub fn dec8(raw: u8, i: usize) -> u8 {
    raw ^ mask8(i)
}

#[inline(always)]
pub fn dec16(raw: u16, i: usize) -> u16 {
    raw ^ mask16(i)
}
