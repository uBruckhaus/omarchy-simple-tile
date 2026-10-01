const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const qml = fs.readFileSync(path.join(__dirname, '../BarWidget.qml'), 'utf8');
for (const succeeds of [true, false]) {
    test(`clear all presets, settings save succeeds: ${succeeds}`, () => {
        const original = {maxWindows: 3, active: true, workspaceLayouts: {'2': {autostart: true}}, workspaceCaps: {'2': 4}, workspaceModes: {'2': 'manual'}, workspaceAutoPresets: {'2': 'grid'}};
        const state = vm.createContext({settings: original, moduleName: 'ubruckhaus.simple-tile', confirmClearAll: true,
            applyPresetWorker: {running: false}, bar: {shell: {updateEntryInline: () => succeeds}}, helperScriptPath: () => '/helper.py'});
        state.root = state;
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
        bar: {shell: {updateEntryInline: () => {throw new Error('unnecessary write')}}}});
    vm.runInContext(qml.match(/    function saveSettingsEntry\([^]*?\n    }/)[0], state);
    assert.equal(state.saveSettingsEntry({id: state.moduleName, workspaceLayouts: {}}), true);
});
