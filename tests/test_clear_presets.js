const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const english = require('./english');
const qml = fs.readFileSync(path.join(__dirname, '../BarWidget.qml'), 'utf8');
for (const succeeds of [true, false]) {
    test(`clear all presets, settings save succeeds: ${succeeds}`, () => {
        const original = {maxWindows: 3, active: true, workspaceLayouts: {'2': {autostart: true}}, workspaceCaps: {'2': 4}, workspaceModes: {'2': 'manual'}, workspaceAutoPresets: {'2': 'grid'}};
        const state = vm.createContext({settings: original, moduleName: 'ubruckhaus.simple-tile', confirmClearAll: true,
            applyPresetWorker: {running: false}, autostartFollows() {}, runHelper(key, args) { this.applyPresetWorker.command = ['python3', this.helperScriptPath()].concat(args); this.applyPresetWorker.running = true; }, dropHelperJobs() {}, bar: {shell: {updateEntryInline: () => succeeds}}, helperScriptPath: () => '/helper.py'});
        state.root = state;
        Object.assign(state, english);
        vm.runInContext(qml.match(/    function saveSettingsEntry\([^]*?\n    }/)[0], state);
        vm.runInContext(qml.match(/    function clearAllPresets\([^]*?\n    }/)[0], state);
        state.clearAllPresets();
        assert.equal(state.failed, !succeeds);
        assert.equal(state.applyPresetWorker.running, succeeds);
        if (succeeds) {
            for (const key of ['workspaceLayouts', 'workspaceCaps', 'workspaceModes', 'workspaceAutoPresets'])
                assert.equal(JSON.stringify(state.settings[key]), '{}');
            assert.ok(Object.values(state.settings.defaultAutoPresets).every(p => p === 'none'));
            assert.equal(state.settings.maxWindows, 3);
            assert.equal(state.settings.active, true);
            assert.equal(state.applyPresetWorker.command[2], '--remove-all-presets');
        } else {
            assert.equal(state.settings, original);
            assert.equal(state.confirmClearAll, true);
        }
    });
}

test('unchanged settings succeed without asking shell to write again', () => {
    const state = vm.createContext({settings: {workspaceLayouts: {}}, moduleName: 'ubruckhaus.simple-tile',
        autostartFollows() {}, bar: {shell: {updateEntryInline: () => {throw new Error('unnecessary write')}}}});
    vm.runInContext(qml.match(/    function saveSettingsEntry\([^]*?\n    }/)[0], state);
    assert.equal(state.saveSettingsEntry({id: state.moduleName, workspaceLayouts: {}}), true);
});

test('autostart copy follows what the panel saves', () => {
    const calls = [];
    const state = vm.createContext({approveAutostartSoon: (ws, on, layout) => calls.push([ws, on, layout && layout.apps.map(a => a.desktop_id)])});
    for (const name of ['capLayouts', 'autostartFollows'])
        vm.runInContext(qml.match(new RegExp('    function ' + name + '\\([^]*?\\n    }'))[0], state);
    const apps = [{desktop_id: 'foot'}, {desktop_id: 'gimp'}];
    const off = {'3': {autostart: false, apps, windows: []}};
    const on = {'3': {autostart: true, apps, windows: []}};
    state.autostartFollows(off, on);                                         // switched on: the shown apps
    state.autostartFollows(on, {'3': {autostart: true, apps: apps.slice(0, 1), windows: []}});   // an app removed
    state.autostartFollows(on, {'3': {autostart: true, apps, windows: [], saveApps: false}});     // Save apps off
    state.autostartFollows(on, off);                                         // switched off: forgotten
    state.autostartFollows(on, {});                                          // App Preset removed: forgotten
    state.autostartFollows(on, on);                                          // nothing changed: nothing sent
    assert.deepEqual(JSON.parse(JSON.stringify(calls)), [[3, true, ['foot', 'gimp']], [3, true, ['foot']],
        [3, true, ['foot', 'gimp']], [3, false, null], [3, false, null]]);
});
