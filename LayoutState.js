// Shared snapshot edits. Removing an app must also remove its restore slots.
function matchesApp(window, app) {
    var savedApp = window.app || window
    // Prefer window classes: different web apps may share a browser launcher.
    var windowClass = String(window.class || savedApp.class || "").toLowerCase()
    var appClass = String(app.class || "").toLowerCase()
    if (windowClass && appClass) return windowClass === appClass
    if (savedApp.desktop_id && app.desktop_id)
        return savedApp.desktop_id === app.desktop_id
    if (savedApp.desktop_path && app.desktop_path)
        return savedApp.desktop_path === app.desktop_path
    return false
}

function removeApp(snapshot, index) {
    var apps = (snapshot.apps || []).slice()
    if (index < 0 || index >= apps.length) return null
    var removed = apps.splice(index, 1)[0]
    var result = Object.assign({}, snapshot, { apps: apps })
    if (Array.isArray(snapshot.windows)) {
        result.windows = snapshot.windows.filter(function(window) {
            return !matchesApp(window, removed)
        })
        result.count = result.windows.length
    } else {
        result.count = apps.length
    }
    if (result.count === 0) result.autostart = false
    return result
}
