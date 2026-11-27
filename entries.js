.pragma library

// Presentation helpers for the panel: which icon a result shows. Nothing
// here ranks or reorders.

function payloadObject(entry) {
    var payload = entry ? entry.payload : null;
    return payload && typeof payload === "object" ? payload : null;
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
