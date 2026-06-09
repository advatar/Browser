// Compiles blst's amalgamated implementation in pure-C (no assembly) mode (__BLST_NO_ASM__ is set
// via the package's cSettings). On 64-bit targets blst's vect.h keeps 64-bit limbs, but its
// reference C in no_asm.h only declares the double-width `llimb_t` for 32-bit limbs (the 64-bit
// path normally uses assembly). Provide the correct 128-bit limb type so the pure-C field
// arithmetic builds on arm64/x86_64.
typedef __uint128_t llimb_t;
#include "../../Vendor/blst/src/server.c"
