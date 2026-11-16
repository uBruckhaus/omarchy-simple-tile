.pragma library

// The queue of newly opened windows the tiling helper still has to place.
// Bounded on purpose (marketplace review #14100): an application that opens
// and closes windows faster than the helper runs must not make it grow
// without limit in the shared shell.

var MAX_PENDING = 32

function normalize(address) {
    var a = String(address || "").toLowerCase()
    if (a.indexOf("0x") === 0) a = a.slice(2)
    return /^[0-9a-f]{1,16}$/.test(a) ? a : ""
}

// openwindow: append once; when full, the oldest entry is dropped.
function enqueue(queue, address) {
    var a = normalize(address)
    if (!a) return queue
    var out = []
    for (var i = 0; i < queue.length; i++) if (queue[i] !== a) out.push(queue[i])
    out.push(a)
    while (out.length > MAX_PENDING) out.shift()
    return out
}

// closewindow: a closed window needs no placing.
function remove(queue, address) {
    var a = normalize(address)
    if (!a || queue.indexOf(a) < 0) return queue
    return queue.filter(function(q) { return q !== a })
}
