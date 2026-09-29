const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {test} = require('node:test');
const path = require('node:path');
const state = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../LayoutState.js'), 'utf8'), state);
const term = {class: 'foot', desktop_id: 'foot'};
const browser = {class: 'chrome', desktop_id: 'chrome'};

test('remove all saved windows for the app, keep other apps and original snapshot', () => {
    const snapshot = {apps: [term, browser], windows: [{class: 'foot'}, {class: 'foot'}, {class: 'chrome'}], count: 3, autostart: true};
    const result = state.removeApp(snapshot, 0);
    assert.equal(result.apps.length, 1);
    assert.equal(result.windows.length, 1);
    assert.equal(result.windows[0].class, 'chrome');
    assert.equal(result.count, 1);
    assert.equal(result.autostart, true);
    assert.equal(snapshot.windows.length, 3);
    assert.equal(snapshot.apps.length, 2);
});
test('remove final app disables autostart', () => {
    const result = state.removeApp({apps: [term], windows: [{class: 'foot'}], autostart: true}, 0);
    assert.equal(result.count, 0);
    assert.equal(result.autostart, false);
    assert.equal(result.windows.length, 0);
});
test('browser app classes take precedence over shared desktop launcher', () => {
    assert.equal(state.matchesApp({class: 'youtube', app: browser}, browser), false);
    assert.equal(state.matchesApp({class: 'CHROME', app: browser}, browser), true);
});
test('legacy snapshots and invalid indexes', () => {
    assert.equal(state.removeApp({apps: [term, browser]}, 0).count, 1);
    assert.equal(state.removeApp({apps: [term]}, 5), null);
    assert.equal(state.removeApp({apps: [term]}, -1), null);
});
