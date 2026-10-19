// The plugin's own English texts for functions lifted out of BarWidget.qml:
// they call root.t() and root.tn(), which the widget gets from I18n.js.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const i18n = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../I18n.js'), 'utf8').replace('.pragma library', ''), i18n);

module.exports = {
    t: (key, args) => i18n.tr('en', key, args),
    tn: (key, n, args) => i18n.trn('en', key, n, args),
};
