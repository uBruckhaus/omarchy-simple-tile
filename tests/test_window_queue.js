const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {test} = require('node:test');
const path = require('node:path');
const Q = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../WindowQueue.js'), 'utf8').replace(/^\.pragma library\s*\n/, ''), Q);
const same = (a, b) => assert.deepEqual(JSON.parse(JSON.stringify(a)), b);

test('addresses are normalized and deduplicated', () => {
    let q = Q.enqueue([], '0xABC');
    q = Q.enqueue(q, 'abc');
    q = Q.enqueue(q, 'def');
    same(q, ['abc', 'def']);
    same(Q.enqueue(q, 'not-hex'), ['abc', 'def']);
    same(Q.enqueue(q, ''), ['abc', 'def']);
    same(Q.enqueue(q, '1'.repeat(17)), ['abc', 'def']);
});

test('closed windows leave the queue', () => {
    same(Q.remove(['abc', 'def'], '0xabc'), ['def']);
    same(Q.remove(['abc'], 'fff'), ['abc']);
});

test('an open/close flood keeps the queue bounded', () => {
    let q = [];
    for (let i = 0; i < 100000; i++) {
        q = Q.enqueue(q, i.toString(16));
        if (i % 2) q = Q.remove(q, i.toString(16));
        assert.ok(q.length <= Q.MAX_PENDING);
    }
    let r = [];
    for (let i = 0; i < 1000; i++) r = Q.enqueue(r, i.toString(16));
    assert.equal(r.length, Q.MAX_PENDING);
    assert.equal(r[r.length - 1], (999).toString(16));
});
