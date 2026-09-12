// Canonical mulberry32, copied unmodified, used to pin the Python and Swift ports.
// Run: node spikes/mulberry_reference.js
// The Python port in server/app/battle.py must print identical values.
function mulberry32(a) {
    return function() {
      var t = a += 0x6D2B79F5;
      t = Math.imul(t ^ t >>> 15, t | 1);
      t ^= t + Math.imul(t ^ t >>> 7, t | 61);
      return ((t ^ t >>> 14) >>> 0);
    }
}
for (const seed of [1, 0, 2967037554, 744262745]) {
  const next = mulberry32(seed);
  console.log(seed, [next(), next(), next(), next(), next()].join(','));
}
