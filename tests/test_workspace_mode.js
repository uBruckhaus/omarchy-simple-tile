const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {test} = require('node:test');
const path = require('node:path');
const qml = fs.readFileSync(path.join(__dirname, '../BarWidget.qml'), 'utf8');

function workspace(saved = false, saveSucceeds = true) {
    const state = vm.createContext({
        settings: {}, moduleName: 'ubruckhaus.simple-tile',
        workspaceModes: {}, workspaceLayouts: saved ? {'2': {mode: 'manual', apps: ['terminal']}} : {},
        workspaceAutoPresets: {'2': 'columns'}, workspaceCaps: {'2': 3},
        defaultAutoPresets: {'2': 'stacked'}, cap: 2,
        failedAppNames: {}, failedAppDetails: {},
        failed: false, activeWorkspaceTab: 'presets', lastMessage: '',
        applyPresetWorker: {running: false},
        bar: {shell: {updateEntryInline: () => saveSucceeds}},
    });
    state.root = state;
    state.helperScriptPath = () => '/plugin/simple_tile.py';
    for (const name of ['saveSettingsEntry', 'setWorkspaceMode', 'updateSetting', 'isWorkspaceManual',
                        'autoPresetForWorkspace', 'defaultAutoPresetFor', 'effectiveCapFor',
                        'hasCustomCap', 'autoPresetLabel', 'setWorkspaceAutoPreset',
                        'isWorkspaceNative', 'selectedWindowCap', 'setWorkspaceCap',
                        'recordFailedApps', 'isAppFailed', 'restoreFailureText', 'restoreWorkspaceApps']) {
        const match = qml.match(new RegExp('    function ' + name + '\\([^]*?\\n    }'));
        assert.ok(match, name);
        vm.runInContext(match[0], state);
    }
    // Model QML's setting bindings after a settings assignment.
    let settings = {};
    Object.defineProperty(state, 'settings', {
        get: () => settings,
        set: value => {
            settings = value;
            for (const key of ['workspaceModes', 'workspaceLayouts', 'workspaceAutoPresets', 'workspaceCaps'])
                if (value[key]) state[key] = value[key];
        },
    });
    return state;
}

for (const saved of [false, true]) {
    test(`App Presets enables manual mode, saved snapshot: ${saved}`, () => {
        const state = workspace(saved);
        const snapshot = JSON.stringify(state.workspaceLayouts);
        state.setWorkspaceMode(2, 'manual');
        assert.equal(state.workspaceModes['2'], 'manual');
        assert.equal(state.isWorkspaceManual(2), true);
        assert.equal(state.isWorkspaceManual(1), false);
        assert.equal(state.activeWorkspaceTab, 'manual');
        assert.equal(state.applyPresetWorker.running, false);
        assert.equal(JSON.stringify(state.workspaceLayouts), snapshot);
        state.setWorkspaceMode(2, 'auto');
        assert.equal(state.isWorkspaceManual(2), false);
        assert.equal(state.activeWorkspaceTab, 'presets');
        assert.deepEqual(Array.from(state.applyPresetWorker.command).slice(-3), ['--apply-preset', '2', 'columns']);
        assert.equal(JSON.stringify(state.workspaceLayouts), snapshot);
    });
}
test('Presets uses default without a workspace preset and supports native layout', () => {
    const state = workspace();
    state.workspaceAutoPresets = {};
    state.workspaceCaps = {};
    state.setWorkspaceMode(2, 'auto');
    assert.equal(state.applyPresetWorker.command.at(-1), 'stacked');
    state.workspaceAutoPresets = {'2': 'none'};
    state.setWorkspaceMode(2, 'auto');
    assert.equal(state.applyPresetWorker.command.at(-1), 'none');
});
test('failed settings save does not switch tab or apply a layout', () => {
    const state = workspace(false, false);
    state.setWorkspaceMode(2, 'manual');
    assert.equal(state.failed, true);
    assert.equal(state.activeWorkspaceTab, 'presets');
    assert.equal(state.workspaceModes['2'], undefined);
    assert.equal(state.applyPresetWorker.running, false);
});
test('choosing a geometric preset from manual mode preserves the saved apps', () => {
    const state = workspace(true);
    const snapshot = JSON.stringify(state.workspaceLayouts);
    state.setWorkspaceMode(2, 'manual');
    state.setWorkspaceAutoPreset(2, 'grid');
    assert.equal(state.isWorkspaceManual(2), false);
    assert.equal(JSON.stringify(state.workspaceLayouts), snapshot);
    assert.equal(state.applyPresetWorker.command.at(-1), 'grid');
});
test('click handlers activate the selected workspace mode', () => {
    assert.match(qml, /onClicked: root\.setWorkspaceMode\(root\.selectedWorkspace, "manual"\)/);
    assert.match(qml, /onClicked: root\.setWorkspaceMode\(root\.selectedWorkspace, "auto"\)/);
});

test('Native clears the selected limit and remains Native on repeated clicks', () => {
    const state = workspace();
    state.setWorkspaceAutoPreset(2, 'none');
    assert.equal(state.isWorkspaceNative(2), true);
    assert.equal(state.selectedWindowCap(2), 0);
    assert.equal(state.selectedWindowCap(1), 2);
    assert.equal(state.applyPresetWorker.command.at(-2), '--remove-preset');
    state.setWorkspaceAutoPreset(2, 'none');
    assert.equal(state.selectedWindowCap(2), 0);
    state.setWorkspaceMode(2, 'auto');
    assert.match(state.lastMessage, /no window limit or automatic overflow/);
});
test('choosing a limit exits Native and applies the default geometric preset', () => {
    const state = workspace();
    state.setWorkspaceAutoPreset(2, 'none');
    state.setWorkspaceCap(2, 2);
    assert.equal(state.isWorkspaceNative(2), false);
    assert.equal(state.selectedWindowCap(2), 2);
    assert.equal(state.applyPresetWorker.command.at(-1), 'stacked');
});
test('choosing a geometric preset exits Native and restores its remembered cap', () => {
    const state = workspace();
    state.setWorkspaceAutoPreset(2, 'none');
    state.setWorkspaceAutoPreset(2, 'columns');
    assert.equal(state.isWorkspaceNative(2), false);
    assert.equal(state.selectedWindowCap(2), 3);
});

test('restore warnings retain readable reasons and clear on a successful retry', () => {
    const state = workspace();
    const chrome = {name: 'Google Chrome'};
    state.recordFailedApps(2, [{name: 'Google Chrome', reason: 'window_timeout'}]);
    state.recordFailedApps(1, [{name: 'Terminal', reason: 'launch_failed'}]);
    assert.equal(state.isAppFailed(2, chrome), true);
    assert.match(state.restoreFailureText(2), /Google Chrome: No matching window appeared/);
    state.recordFailedApps(2, []);
    assert.equal(state.isAppFailed(2, chrome), false);
    assert.equal(state.restoreFailureText(2), '');
    assert.match(state.restoreFailureText(1), /Terminal: The app could not be launched/);
});
test('layout restore failures preserve the actual diagnostic', () => {
    const state = workspace();
    state.recordFailedApps(2, [{name: 'Layout', reason: 'Saved tile positions could not be restored'}]);
    assert.equal(state.restoreFailureText(2), 'Layout: Saved tile positions could not be restored');
});

test('restore command captures target workspace independently of the active workspace', () => {
    const state = workspace();
    state.actionWorker = {running: false};
    state.autostartWorker = {running: false};
    state.currentWsId = 1;
    state.selectedWorkspace = 2;
    state.restoreWorkspaceApps(2, 'close');
    state.selectedWorkspace = 1;
    assert.equal(state.actionWorker.targetWs, 2);
    assert.deepEqual(Array.from(state.actionWorker.command).slice(-4), ['--restore-workspace', '2', '--conflict-action', 'close']);
    state.recordFailedApps(2, [{name: 'Chrome', reason: 'close_timeout'}]);
    assert.match(state.restoreFailureText(2), /Check Workspace 2 for a save or close-confirmation dialog/);
});
