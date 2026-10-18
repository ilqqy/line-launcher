.pragma library

// Presentation helpers for the panel: which category chips exist, whether an
// entry belongs to one, and which icon a result shows. Nothing here ranks or
// reorders -- a chip only ever hides entries from the list the shell ranked.

var allKey = "all";

// Chips are the freedesktop main categories. Additional categories
// (WebBrowser, TextEditor, GTK, X-...) are not chips of their own: an entry
// always carries a main category alongside them.
var groups = [
    { key: "development", label: "Development", members: ["Development"] },
    { key: "education", label: "Education", members: ["Education"] },
    { key: "games", label: "Games", members: ["Game"] },
    { key: "graphics", label: "Graphics", members: ["Graphics"] },
    { key: "internet", label: "Internet", members: ["Network"] },
    { key: "media", label: "Media", members: ["AudioVideo", "Audio", "Video"] },
    { key: "office", label: "Office", members: ["Office"] },
    { key: "science", label: "Science", members: ["Science"] },
    { key: "settings", label: "Settings", members: ["Settings"] },
    { key: "system", label: "System", members: ["System"] },
    { key: "utilities", label: "Utilities", members: ["Utility"] }
];

// Works on both plain arrays and the QStringList a DesktopEntry exposes.
function groupKeys(categories) {
    var keys = [];
    if (!categories)
        return keys;

    for (var g = 0; g < groups.length; g++) {
        var members = groups[g].members;
        var hit = false;
        for (var i = 0; i < categories.length && !hit; i++) {
            for (var m = 0; m < members.length; m++) {
                if (categories[i] === members[m]) {
                    hit = true;
                    break;
                }
            }
        }
        if (hit)
            keys.push(groups[g].key);
    }
    return keys;
}

// `records` are DrunProvider's candidate records. "All" first, then every
// main category that has at least one application, alphabetically.
function chipsFor(records) {
    var counts = {};
    var list = records || [];
    for (var r = 0; r < list.length; r++) {
        var keys = groupKeys(list[r].categories);
        for (var k = 0; k < keys.length; k++)
            counts[keys[k]] = (counts[keys[k]] || 0) + 1;
    }

    var chips = [{ key: allKey, label: "All", count: list.length }];
    for (var g = 0; g < groups.length; g++) {
        if (counts[groups[g].key] > 0)
            chips.push({ key: groups[g].key, label: groups[g].label, count: counts[groups[g].key] });
    }
    return chips;
}

function payloadObject(entry) {
    var payload = entry ? entry.payload : null;
    return payload && typeof payload === "object" ? payload : null;
}

// Only entries whose payload carries desktop categories can be in one;
// actions, commands and piped lines belong to "All" alone.
function entryIn(entry, key) {
    if (key === allKey)
        return true;
    var payload = payloadObject(entry);
    if (!payload || !payload.categories)
        return false;
    return groupKeys(payload.categories).indexOf(key) >= 0;
}

// The icon name or path a result asks for; "" leaves it to the fallback.
// Shell commands carry no icon of their own and get `commandIcon`
// (Theme.commandIcon at the call sites).
function iconFor(entry, commandIcon) {
    var payload = payloadObject(entry);
    if (payload && typeof payload.icon === "string" && payload.icon !== "")
        return payload.icon;
    if (entry && entry.source && entry.source.literalMatching)
        return commandIcon || "";
    return "";
}
