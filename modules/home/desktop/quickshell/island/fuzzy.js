// Fuzzy ranking for the island launcher. Plain JS, no `.pragma library`:
// node must parse this file for fuzzy.test.js, and the single QML
// consumer makes library sharing moot.
// Spec: docs/superpowers/specs/2026-07-08-island-launcher-design.md
//
// tier(query, name) -> 0 empty-query match-all; 1 prefix; 2 word start;
// 3 substring; 4 scattered subsequence; -1 no match. Lower is better;
// ties break alphabetically at the call site. Case-insensitive.
function tier(query, name) {
    var q = query.toLowerCase();
    var n = name.toLowerCase();
    if (q.length === 0)
        return 0;
    if (n.indexOf(q) === 0)
        return 1;
    var words = n.split(/[\s\-_.]+/);
    for (var i = 1; i < words.length; i++) {
        if (words[i].indexOf(q) === 0)
            return 2;
    }
    if (n.indexOf(q) !== -1)
        return 3;
    var pos = 0;
    for (var j = 0; j < q.length; j++) {
        pos = n.indexOf(q.charAt(j), pos);
        if (pos === -1)
            return -1;
        pos += 1;
    }
    return 4;
}

// node hook for fuzzy.test.js; inert under QML.
if (typeof module !== "undefined")
    module.exports = { tier: tier };
