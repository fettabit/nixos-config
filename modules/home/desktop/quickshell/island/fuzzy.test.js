// Node smoke test for fuzzy.js (not loaded by QML — nothing imports it).
// Run: node modules/home/desktop/quickshell/island/fuzzy.test.js
const assert = require("node:assert");
const { tier } = require("./fuzzy.js");

// Spec worked examples for query "co"
assert.strictEqual(tier("co", "Code"), 1, "prefix");
assert.strictEqual(tier("co", "VS Code"), 2, "word start");
assert.strictEqual(tier("co", "Discord"), 3, "substring");
assert.strictEqual(tier("co", "Calculator"), 4, "scattered subsequence");
assert.strictEqual(tier("co", "Kitty"), -1, "no match");

// Empty query matches everything at tier 0
assert.strictEqual(tier("", "Anything"), 0, "empty query");

// Case-insensitive both ways
assert.strictEqual(tier("FIRE", "firefox"), 1, "query case folded");
assert.strictEqual(tier("fire", "FIREFOX"), 1, "name case folded");

// Word boundaries: space, dash, underscore, dot
assert.strictEqual(tier("burn", "wallpaper-burn"), 2, "dash boundary");
assert.strictEqual(tier("view", "image_viewer"), 2, "underscore boundary");
assert.strictEqual(tier("org", "chromium.org"), 2, "dot boundary");

// Subsequence must respect letter order
assert.strictEqual(tier("xf", "Firefox"), -1, "subsequence respects order");

console.log("fuzzy.js: all assertions passed");
