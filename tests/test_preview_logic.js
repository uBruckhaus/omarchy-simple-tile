const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {test} = require('node:test');
const path = require('node:path');
const L = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../PreviewLogic.js'), 'utf8').replace(/^\.pragma library\s*\n/, ''), L);
// Objects made inside the context have its prototypes: compare as JSON.
const same = (a, b) => assert.deepEqual(JSON.parse(JSON.stringify(a)), b);

test('drop zone picks the layout for the new limit', () => {
    assert.equal(L.addZonePreset(2, 0.5, 0.05), 'stacked');
    assert.equal(L.addZonePreset(2, 0.05, 0.5), 'side-by-side');
    assert.equal(L.addZonePreset(3, 0.1, 0.5), 'master-left');
    assert.equal(L.addZonePreset(3, 0.9, 0.5), 'master-right');
    assert.equal(L.addZonePreset(3, 0.5, 0.1), 'columns');
    assert.equal(L.addZonePreset(3, 0.1, 0.1), 'master-left');
    assert.equal(L.addZonePreset(4, 0.1, 0.1), 'grid');
    assert.equal(L.addZonePreset(4, -3, 9), 'grid');
    assert.equal(L.addZonePreset(1, 0.5, 0.5), null);
    for (const cap of [2, 3, 4]) for (const u of [0, 0.2, 0.5, 0.8, 1]) for (const v of [0, 0.2, 0.5, 0.8, 1])
        assert.ok(L.TILING_BY_CAP[String(cap)].includes(L.addZonePreset(cap, u, v)));
});

test('add window raises the limit with the dropped layout; a click pins nothing', () => {
    let e = {maxWindows: 2, workspaceCaps: {'3': 2}};
    same(L.addWindow(e, 3, 'columns'), ['apply', 3, 'columns']);
    assert.equal(e.workspaceCaps['3'], 3);
    assert.equal(e.workspaceAutoPresets['3'], 'columns');
    e = {maxWindows: 2, workspaceCaps: {'3': 2}};
    assert.equal(L.addWindow(e, 3, null), null);
    assert.equal((e.workspaceAutoPresets || {})['3'], undefined);
    e = {maxWindows: 2, workspaceCaps: {'3': 2}, workspaceAutoPresets: {'3': 'stacked'}};
    same(L.addWindow(e, 3, null), ['apply', 3, 'master-left']);          // no Stacked with 3
    e = {maxWindows: 2, workspaceCaps: {'1': 4}};
    assert.equal(L.canAddWindow(e, 1), false);
    assert.equal(L.addWindow(e, 1, 'grid'), null);
    const manual = {workspaceModes: {'2': 'manual'}, workspaceLayouts: {'2': {mode: 'manual'}}};
    assert.equal(L.canAddWindow(manual, 2), false);
    e = {maxWindows: 2};
    assert.equal(L.addWindow(e, 0, 'master-right'), null);
    assert.equal(e.maxWindows, 3);
    assert.equal(e.defaultAutoPresets['3'], 'master-right');
});

test('+ on a free workspace means tile with 2 windows', () => {
    const e = {maxWindows: 4, workspaceAutoPresets: {'3': 'none'}};
    assert.equal(L.tilesFreely(e, 3), true);
    assert.equal(L.addedCap(e, 3), 2);
    assert.equal(L.addedCap({maxWindows: 2}, 3, {'3': 'floating'}), 2);
    assert.equal(L.addedCap({maxWindows: 4}, 3), null);
});

test('columns divider only with three windows and its own range', () => {
    assert.equal(L.hasDivider('columns', 3), true);
    assert.equal(L.hasDivider('columns', 4), false);
    assert.equal(L.hasDivider('grid', 4), false);
    let e = {maxWindows: 3, workspaceAutoPresets: {'5': 'columns'}};
    same(L.setSplit(e, 5, 0.9), ['apply', 5, 'columns']);
    assert.equal(e.workspaceSplits['5'], 0.6);
    e = {maxWindows: 3, workspaceAutoPresets: {'5': 'master-left'}};
    L.setSplit(e, 5, 0.9);
    assert.equal(e.workspaceSplits['5'], 0.8);
    L.setSplit(e, 5, null);
    assert.equal(e.workspaceSplits['5'], undefined);
    const r = L.presetRects('columns', 3, 0.5);
    assert.ok(Math.abs(r[1][2] - (1 - 4 * L.GAP) * 0.5) < 1e-9);
    assert.ok(Math.abs(r[0][2] - r[2][2]) < 1e-9);
});

test('tray offers the layouts for the limit and one window fewer', () => {
    const e = {maxWindows: 3};
    const tray = L.trayTargets(e, 1, 3);
    same(tray.map(t => t.preset), ['master-left', 'master-right', 'columns', 'side-by-side']);
    assert.equal(tray[0].current, true);
    assert.equal(tray[3].fewer, true);
    same(L.trayTargets(e, 1, 1), []);
});

const windows = () => [
    {class: 'a', at: [0, 0], size: [950, 1000], floating: false},
    {class: 'b', at: [960, 0], size: [960, 495], floating: false},
    {class: 'c', at: [960, 505], size: [960, 495], floating: false},
    {class: 'f', at: [300, 300], size: [400, 300], floating: true}];

test('saved cuts and moving one', () => {
    const cuts = L.savedCuts(windows());
    same(cuts, [{axis: 0, edge: 950, start: 960}, {axis: 1, edge: 495, start: 505}]);
    const moved = L.moveSavedCut(windows(), 0, 950, 960, 1155);
    same(moved[0].size, [1150, 1000]);
    same([moved[1].at, moved[1].size], [[1160, 0], [760, 495]]);
    same(moved[3], windows()[3]);
    assert.equal(L.moveSavedCut(windows(), 0, 950, 960, 1900), null);
    assert.equal(L.layoutTreeOk(windows().slice(0, 3)), true);
    assert.equal(L.layoutTreeOk([{at: [0, 0], size: [10, 10]}, {at: [5, 5], size: [10, 10]}]), false);
});

test('floating resize, add app, swap saved', () => {
    const out = L.resizeSavedFloating(windows(), 3, 5, 5);
    same(out[3].size, [192, 100]);
    assert.equal(L.resizeSavedFloating(windows(), 0, 600, 500), null);
    const e = {workspaceModes: {'4': 'manual'}, workspaceLayouts: {'4': {mode: 'manual', apps: [{class: 'a'}], windows: windows()}}};
    L.addSavedApp(e, 4, {name: 'Web', desktop_id: 'chromium', startup_class: 'Chromium', exec: 'chromium'});
    const w = e.workspaceLayouts['4'].windows;
    same(w[0].size, [950, 495]);
    same([w[4].at, w[4].size], [[0, 505], [950, 495]]);
    assert.equal(w[4].class, 'Chromium');
    assert.equal(w[4].app.exec, undefined);
    assert.equal(e.workspaceLayouts['4'].count, 5);
    L.swapSaved(e, 4, 1, 2);
    same(e.workspaceLayouts['4'].windows[1].at, [960, 505]);
});

test('undo takes back only this change', () => {
    const before = {maxWindows: 2, workspaceCaps: {'1': 2}, workspaceAutoPresets: {'1': 'side-by-side'}};
    const after = {maxWindows: 2, workspaceCaps: {'1': 3}, workspaceAutoPresets: {'1': 'columns'}};
    let current = {maxWindows: 4, workspaceCaps: {'1': 3, '2': 4}, workspaceAutoPresets: {'1': 'columns'}};
    assert.equal(L.undoMerge(current, before, after), true);
    same(current, {maxWindows: 4, workspaceCaps: {'1': 2, '2': 4}, workspaceAutoPresets: {'1': 'side-by-side'}});
    current = {maxWindows: 2, workspaceCaps: {'1': 3, '2': 4}};
    L.undoMerge(current, {maxWindows: 2}, {maxWindows: 2, workspaceCaps: {'1': 3}});
    same(current, {maxWindows: 2, workspaceCaps: {'2': 4}});
    current = {maxWindows: 2};
    assert.equal(L.undoMerge(current, {workspaceSplits: {'1': 0.6}}, {}), true);
    same(current.workspaceSplits, {'1': 0.6});
    assert.equal(L.undoMerge({maxWindows: 4}, {maxWindows: 2}, {maxWindows: 3}), false);
});

test('minus: one fewer, then the default limit', () => {
    const e = {maxWindows: 3, workspaceCaps: {'4': 2}};
    assert.equal(L.removedCap(e, 4), 1);
    L.removeWindow(e, 4);
    assert.equal(e.workspaceCaps['4'], 1);
    assert.equal(L.removedCap(e, 4), 3);
    e.workspaceAutoPresets = {'4': 'side-by-side'};
    same(L.removeWindow(e, 4), ['apply', 4, 'master-left']);
    assert.equal(e.workspaceCaps['4'], undefined);
    assert.equal(L.removedCap({maxWindows: 1}, 4), null);
    const g = {maxWindows: 1};
    assert.equal(L.removedCap(g, 0), 2);
    L.removeWindow(g, 0);
    assert.equal(g.maxWindows, undefined);
    assert.equal(L.removedCap({maxWindows: 2, workspaceAutoPresets: {'3': 'none'}}, 3), null);
});
