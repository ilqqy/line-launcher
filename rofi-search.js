.pragma library

// Port of Rofi 2.x drun filter + sort (helper.c + drun.c)
// Defaults match stock rofi -dump-config:
//   matching: normal, normalize-match: false, tokenize: true, sort: false
//   sorting-method: normal, drun-match-fields: name,generic,exec,categories,keywords

var FUZZY_SCORER_MAX_LENGTH = 256;
var MIN_SCORE = -2147483647;
var LEADING_GAP_SCORE = -4;
var GAP_SCORE = -5;
var WORD_START_SCORE = 50;
var NON_WORD_SCORE = 40;
var CAMEL_SCORE = WORD_START_SCORE + GAP_SCORE - 1;
var CONSECUTIVE_SCORE = WORD_START_SCORE + GAP_SCORE;
var PATTERN_NON_START_MULTIPLIER = 1;
var PATTERN_START_MULTIPLIER = 2;

var DEFAULT_MATCH_FIELDS = {
    name: true,
    generic: true,
    exec: true,
    categories: true,
    keywords: true,
    comment: false
};

function optionValue(options, key, fallback) {
    if (!options || options[key] === undefined)
        return fallback;
    return options[key];
}

function toCodePoints(text) {
    var points = [];
    var str = String(text || "");
    for (var i = 0; i < str.length; ) {
        var cp = str.codePointAt(i);
        points.push(String.fromCodePoint(cp));
        i += cp > 0xffff ? 2 : 1;
    }
    return points;
}

// helper.c utf8_helper_simplify_string
function simplifyString(text) {
    if (!text)
        return "";

    var out = "";
    var chars = toCodePoints(text);
    for (var i = 0; i < chars.length; i++) {
        var decomposed = chars[i].normalize("NFD");
        out += decomposed.charAt(0);
    }
    return out;
}

function escapeRegex(input) {
    return String(input).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// helper.c glob_to_regex
function globToRegex(input) {
    var escaped = escapeRegex(input);
    var chars = toCodePoints(escaped);
    var pattern = "";

    for (var i = 0; i < chars.length; i++) {
        var ch = chars[i];
        if (ch === "\\" && i + 1 < chars.length) {
            var next = chars[i + 1];
            if (next === "*") {
                pattern += ".";
                i++;
                continue;
            }
            if (next === "?") {
                pattern += "S";
                i++;
                continue;
            }
        }
        pattern += ch;
    }

    return pattern;
}

// helper.c fuzzy_to_regex
function fuzzyToRegex(input) {
    var escaped = escapeRegex(input);
    var chars = toCodePoints(escaped);
    if (chars.length === 0)
        return ".*";

    var pattern = "";
    for (var i = 0; i < chars.length; i++) {
        if (i > 0)
            pattern += ".*?";

        if (chars[i] === "\\" && i + 1 < chars.length) {
            pattern += "(" + chars[i] + chars[i + 1] + ")";
            i++;
        } else {
            pattern += "(" + chars[i] + ")";
        }
    }

    return pattern;
}

function prefixRegex(input) {
    return "\\b" + escapeRegex(input);
}

function compileRegex(source, options) {
    var normalizeMatch = optionValue(options, "normalizeMatch", false) === true;
    var caseSensitive = optionValue(options, "caseSensitive", false) === true;
    var pattern = normalizeMatch ? simplifyString(source) : source;
    var flags = caseSensitive ? "" : "i";

    try {
        return new RegExp(pattern, flags);
    } catch (e) {
        return new RegExp(escapeRegex(pattern), flags);
    }
}

// helper.c create_regex
function createRegex(input, options) {
    var negateChar = optionValue(options, "matchingNegateChar", "-");
    var invert = 0;
    var token = String(input || "");

    if (negateChar && negateChar.length > 0 && token.charAt(0) === negateChar) {
        invert = 1;
        token = token.slice(1);
    }

    var method = optionValue(options, "matchingMethod", "normal");
    var normalizeMatch = optionValue(options, "normalizeMatch", false) === true;
    var source = normalizeMatch ? simplifyString(token) : token;
    var pattern;

    switch (method) {
    case "glob":
        pattern = globToRegex(source);
        break;
    case "regex":
        pattern = source;
        break;
    case "fuzzy":
        pattern = fuzzyToRegex(source);
        break;
    case "prefix":
        pattern = prefixRegex(source);
        break;
    case "normal":
    default:
        pattern = escapeRegex(source);
        break;
    }

    return {
        regex: compileRegex(pattern, options),
        invert: invert
    };
}

// helper.c helper_tokenize
function createTokens(pattern, options) {
    if (!pattern)
        return [];

    var tokenize = optionValue(options, "tokenize", true) !== false;
    if (!tokenize)
        return [createRegex(pattern, options)];

    var parts = String(pattern).trim().split(/\s+/).filter(function(part) {
        return part.length > 0;
    });

    var tokens = [];
    for (var i = 0; i < parts.length; i++)
        tokens.push(createRegex(parts[i], options));
    return tokens;
}

// helper.c helper_token_match
function helperTokenMatch(token, text, options) {
    if (!text)
        return false;

    var normalizeMatch = optionValue(options, "normalizeMatch", false) === true;
    var haystack = normalizeMatch ? simplifyString(text) : String(text);
    var match = true;

    token.regex.lastIndex = 0;
    match = token.regex.test(haystack);
    if (token.invert)
        match = !match;

    return match;
}

function matchTokenOnList(token, values, options) {
    for (var i = 0; i < values.length; i++) {
        if (values[i] && helperTokenMatch(token, values[i], options))
            return true;
    }
    return false;
}

function resolveMatchFields(options) {
    if (options && options.matchFields)
        return options.matchFields;
    return DEFAULT_MATCH_FIELDS;
}

// drun.c drun_token_match
function drunTokenMatch(tokens, app, options) {
    if (!tokens || tokens.length === 0)
        return false;

    var fields = resolveMatchFields(options);

    for (var t = 0; t < tokens.length; t++) {
        var token = tokens[t];
        var test = 0;

        if (fields.name && app.name)
            test = helperTokenMatch(token, app.name, options) ? 1 : 0;

        if (test === token.invert && fields.generic && app.genericName)
            test = helperTokenMatch(token, app.genericName, options) ? 1 : 0;

        if (test === token.invert && fields.exec && app.exec)
            test = helperTokenMatch(token, app.exec, options) ? 1 : 0;

        if (test === token.invert && fields.categories && app.categories && app.categories.length) {
            if (matchTokenOnList(token, app.categories, options))
                test = 1;
        }

        if (test === token.invert && fields.keywords && app.keywords && app.keywords.length) {
            if (matchTokenOnList(token, app.keywords, options))
                test = 1;
        }

        if (test === token.invert && fields.comment && app.comment)
            test = helperTokenMatch(token, app.comment, options) ? 1 : 0;

        if (test === 0)
            return false;
    }

    return true;
}

// Best rank among fields that satisfy a single token (lower = stronger match).
function tokenFieldRank(token, app, options) {
    var fields = resolveMatchFields(options);
    var best = 999;

    if (fields.name && app.name && helperTokenMatch(token, app.name, options))
        best = Math.min(best, 0);
    if (fields.generic && app.genericName && helperTokenMatch(token, app.genericName, options))
        best = Math.min(best, 1);
    if (fields.keywords && app.keywords && app.keywords.length) {
        if (matchTokenOnList(token, app.keywords, options))
            best = Math.min(best, 2);
    }
    if (fields.categories && app.categories && app.categories.length) {
        if (matchTokenOnList(token, app.categories, options))
            best = Math.min(best, 3);
    }
    if (fields.comment && app.comment && helperTokenMatch(token, app.comment, options))
        best = Math.min(best, 4);
    if (fields.exec && app.exec && helperTokenMatch(token, app.exec, options))
        best = Math.min(best, 5);

    return best;
}

// Weakest token rank across all tokens — exec-only matches sort below name matches.
function matchFieldRank(tokens, app, options) {
    var worst = 0;

    for (var t = 0; t < tokens.length; t++) {
        var rank = tokenFieldRank(tokens[t], app, options);
        if (rank === 999)
            return 999;
        if (rank > worst)
            worst = rank;
    }

    return worst;
}

function getCharacterClass(ch) {
    if (ch.length !== 1)
        return "NON_WORD";
    if (ch.toLowerCase() !== ch.toUpperCase())
        return ch === ch.toLowerCase() ? "LOWER" : "UPPER";
    if (/\d/.test(ch))
        return "DIGIT";
    return "NON_WORD";
}

function getScoreFor(prev, curr) {
    if (prev === "NON_WORD" && curr !== "NON_WORD")
        return WORD_START_SCORE;
    if ((prev === "LOWER" && curr === "UPPER") || (prev !== "DIGIT" && curr === "DIGIT"))
        return CAMEL_SCORE;
    if (curr === "NON_WORD")
        return NON_WORD_SCORE;
    return 0;
}

// helper.c rofi_scorer_fuzzy_evaluate (sorting-method fzf)
function fuzzyEvaluate(pattern, str, caseSensitive) {
    var patternChars = toCodePoints(pattern).filter(function(ch) { return !/\s/.test(ch); });
    var strChars = toCodePoints(str);
    var slen = strChars.length;
    var plen = patternChars.length;

    if (slen > FUZZY_SCORER_MAX_LENGTH)
        return -MIN_SCORE;
    if (plen === 0)
        return 0;

    var score = new Array(slen);
    var dp = new Array(slen);
    for (var d = 0; d < slen; d++)
        dp[d] = MIN_SCORE;

    var prev = "NON_WORD";
    for (var si = 0; si < slen; si++) {
        var cur = getCharacterClass(strChars[si]);
        score[si] = getScoreFor(prev, cur);
        prev = cur;
    }

    var pfirst = true;
    var pstart = true;

    for (var pi = 0; pi < plen; pi++) {
        var pc = patternChars[pi];
        if (/\s/.test(pc)) {
            pstart = true;
            continue;
        }

        var uleft = 0;
        var ulefts = 0;
        var lefts = MIN_SCORE;

        for (si = 0; si < slen; si++) {
            var left = dp[si];
            lefts = Math.max(lefts + GAP_SCORE, left);
            var sc = strChars[si];
            var matches = caseSensitive
                ? pc === sc
                : pc.toLowerCase() === sc.toLowerCase();

            if (matches) {
                var multiplier = pstart ? PATTERN_START_MULTIPLIER : PATTERN_NON_START_MULTIPLIER;
                var tScore = score[si] * multiplier;
                dp[si] = pfirst
                    ? LEADING_GAP_SCORE * si + tScore
                    : Math.max(uleft + CONSECUTIVE_SCORE, ulefts + tScore);
            } else {
                dp[si] = MIN_SCORE;
            }

            uleft = left;
            ulefts = lefts;
        }

        pfirst = false;
        pstart = false;
    }

    lefts = MIN_SCORE;
    for (si = 0; si < slen; si++)
        lefts = Math.max(lefts + GAP_SCORE, dp[si]);

    return -lefts;
}

// helper.c levenshtein (sorting-method normal)
function levenshtein(needle, haystack, caseSensitive) {
    var needleChars = toCodePoints(needle);
    var haystackChars = toCodePoints(haystack);
    var needleLen = needleChars.length;
    var haystackLen = haystackChars.length;

    if (needleLen === 0)
        return haystackLen;

    var column = new Array(needleLen + 1);
    for (var y = 0; y < needleLen; y++)
        column[y] = y;
    column[needleLen] = needleLen;

    for (var x = 1; x <= haystackLen; x++) {
        var haystackChar = caseSensitive
            ? haystackChars[x - 1]
            : haystackChars[x - 1].toLowerCase();
        column[0] = x;
        var lastdiag = x - 1;

        for (var y = 1; y <= needleLen; y++) {
            var needleChar = caseSensitive
                ? needleChars[y - 1]
                : needleChars[y - 1].toLowerCase();
            var olddiag = column[y];
            column[y] = Math.min(
                column[y] + 1,
                column[y - 1] + 1,
                lastdiag + (needleChar === haystackChar ? 0 : 1)
            );
            lastdiag = olddiag;
        }
    }

    return column[needleLen];
}

function completionName(app) {
    return app.name || "";
}

function desktopIdForApp(app) {
    if (!app || !app.entry)
        return "";
    return app.entry.id || "";
}

// rofi3.druncache format: "{score} {desktop_id}\n" (history.c / drun.c)
var DEFAULT_DRUN_HISTORY_SIZE = 25;

function parseDrunHistoryEntries(text) {
    var entries = [];
    if (!text)
        return entries;

    var lines = String(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line)
            continue;

        var spaceAt = line.indexOf(" ");
        if (spaceAt <= 0)
            continue;

        var index = parseInt(line.slice(0, spaceAt), 10);
        var desktopId = line.slice(spaceAt + 1).trim();
        if (!isNaN(index) && desktopId)
            entries.push({ index: index, id: desktopId });
    }

    return entries;
}

function parseDrunHistory(text) {
    var map = {};
    var entries = parseDrunHistoryEntries(text);

    // drun.c get_apps_history: sort_index = length - line_index
    for (var i = 0; i < entries.length; i++)
        map[entries[i].id] = entries.length - i;

    return map;
}

// history.c history_set + __history_write_element_list
function recordDrunLaunch(cacheText, desktopId, maxSize) {
    if (!desktopId)
        return cacheText || "";

    var limit = maxSize !== undefined ? maxSize : DEFAULT_DRUN_HISTORY_SIZE;
    var list = parseDrunHistoryEntries(cacheText);
    var maxIndex = 0;

    for (var i = list.length - 1; i >= 0; i--) {
        if (list[i].id === desktopId)
            list.splice(i, 1);
        else if (list[i].index > maxIndex)
            maxIndex = list[i].index;
    }

    list.unshift({ index: maxIndex + 1, id: desktopId });

    list.sort(function(a, b) {
        return b.index - a.index;
    });

    if (list.length > limit)
        list = list.slice(0, limit);

    if (list.length === 0)
        return "";

    var minValue = list[list.length - 1].index;
    var lines = [];
    for (var j = 0; j < list.length; j++)
        lines.push(String(list[j].index - minValue) + " " + list[j].id);

    return lines.join("\n") + "\n";
}

function historySortIndex(app, historyMap) {
    if (!historyMap)
        return null;

    var id = desktopIdForApp(app);
    if (!id)
        return null;

    if (historyMap[id] !== undefined)
        return historyMap[id];

    if (id.indexOf(".desktop") === -1 && historyMap[id + ".desktop"] !== undefined)
        return historyMap[id + ".desktop"];

    var slashAt = id.lastIndexOf("/");
    var base = slashAt >= 0 ? id.slice(slashAt + 1) : id;
    if (historyMap[base] !== undefined)
        return historyMap[base];

    return null;
}

// drun.c drun_int_sort_list + get_apps_history
function sortApplicationsLikeRofi(applications, historyMap) {
    var items = [];

    for (var i = 0; i < applications.length; i++) {
        items.push({
            app: applications[i],
            hist: historySortIndex(applications[i], historyMap)
        });
    }

    items.sort(function(a, b) {
        var aInHistory = a.hist !== null;
        var bInHistory = b.hist !== null;

        if (aInHistory && bInHistory)
            return b.hist - a.hist;
        if (aInHistory)
            return -1;
        if (bInHistory)
            return 1;

        return completionName(a.app).localeCompare(completionName(b.app));
    });

    var sorted = [];
    for (var j = 0; j < items.length; j++)
        sorted.push(items[j].app);
    return sorted;
}

function sortDistance(pattern, text, options) {
    var caseSensitive = optionValue(options, "caseSensitive", false) === true;
    var method = optionValue(options, "sortingMethod", "normal");

    if (method === "fzf")
        return fuzzyEvaluate(pattern, text, caseSensitive);

    return levenshtein(pattern, text, caseSensitive);
}

function prepareApplication(entry) {
    return {
        name: entry.name || "",
        genericName: entry.genericName || "",
        exec: entry.execString || "",
        categories: entry.categories ? Array.from(entry.categories) : [],
        keywords: entry.keywords ? Array.from(entry.keywords) : [],
        comment: entry.comment || "",
        entry: entry
    };
}

function parseMatchFields(spec) {
    if (!spec || spec === "all") {
        return {
            name: true,
            generic: true,
            exec: true,
            categories: true,
            keywords: true,
            comment: true
        };
    }

    var enabled = {
        name: false,
        generic: false,
        exec: false,
        categories: false,
        keywords: false,
        comment: false
    };

    spec.split(/[,#]/).map(function(part) { return part.trim().toLowerCase(); }).forEach(function(part) {
        if (part === "name")
            enabled.name = true;
        else if (part === "generic")
            enabled.generic = true;
        else if (part === "exec")
            enabled.exec = true;
        else if (part === "categories")
            enabled.categories = true;
        else if (part === "keywords")
            enabled.keywords = true;
        else if (part === "comment")
            enabled.comment = true;
    });

    return enabled;
}

function search(query, applications, options) {
    var trimmed = (query || "").trim();
    if (trimmed.length === 0)
        return [];

    var searchOptions = {
        matchingMethod: "normal",
        caseSensitive: false,
        normalizeMatch: false,
        tokenize: true,
        sort: false,
        sortingMethod: "normal",
        matchingNegateChar: "-"
    };

    if (options) {
        if (options.matchingMethod !== undefined)
            searchOptions.matchingMethod = options.matchingMethod;
        if (options.caseSensitive !== undefined)
            searchOptions.caseSensitive = options.caseSensitive;
        if (options.normalizeMatch !== undefined)
            searchOptions.normalizeMatch = options.normalizeMatch;
        if (options.tokenize !== undefined)
            searchOptions.tokenize = options.tokenize;
        if (options.sort !== undefined)
            searchOptions.sort = options.sort;
        if (options.sortingMethod !== undefined)
            searchOptions.sortingMethod = options.sortingMethod;
        if (options.matchingNegateChar !== undefined)
            searchOptions.matchingNegateChar = options.matchingNegateChar;
        if (options.matchFieldsSpec !== undefined)
            searchOptions.matchFields = parseMatchFields(options.matchFieldsSpec);
        if (options.matchFields !== undefined)
            searchOptions.matchFields = options.matchFields;
    }

    var tokens = createTokens(trimmed, searchOptions);
    if (tokens.length === 0)
        return [];

    var useDrunHistory = true;
    if (options && options.useDrunHistory === false)
        useDrunHistory = false;

    var appList = applications;
    if (useDrunHistory && options && options.drunHistory)
        appList = sortApplicationsLikeRofi(applications, options.drunHistory);

    var results = [];

    for (var i = 0; i < appList.length; i++) {
        var app = appList[i];
        if (!drunTokenMatch(tokens, app, searchOptions))
            continue;

        var sortText = completionName(app);
        results.push({
            app: app,
            entry: app.entry,
            index: i,
            fieldRank: matchFieldRank(tokens, app, searchOptions),
            distance: searchOptions.sort
                ? sortDistance(trimmed, sortText, searchOptions)
                : i
        });
    }

    if (searchOptions.sort) {
        results.sort(function(a, b) {
            if (a.distance !== b.distance)
                return a.distance - b.distance;
            return completionName(a.entry).localeCompare(completionName(b.entry));
        });
    } else {
        var preferNameMatch = true;
        if (options && options.preferNameMatch === false)
            preferNameMatch = false;

        if (preferNameMatch) {
            var historyMap = (options && options.drunHistory) ? options.drunHistory : null;

            results.sort(function(a, b) {
                if (a.fieldRank !== b.fieldRank)
                    return a.fieldRank - b.fieldRank;

                if (historyMap) {
                    var ha = historySortIndex(a.app, historyMap);
                    var hb = historySortIndex(b.app, historyMap);
                    var aInHistory = ha !== null;
                    var bInHistory = hb !== null;

                    if (aInHistory && bInHistory && ha !== hb)
                        return hb - ha;
                    if (aInHistory !== bInHistory)
                        return aInHistory ? -1 : 1;
                }

                return completionName(a.app).localeCompare(completionName(b.app));
            });
        }
    }

    return results.map(function(result) { return result.entry; });
}
