const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.BILL_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const source = fs.readFileSync('entry/src/main/ets/common/ReminderScheduler.ets', 'utf8');
function fixture(fail = false, remaining = []) {
  const values = new Map([['reminder_enabled', true], ['unrelated', 'keep']]);
  let calls = 0, flushes = 0;
  const prefs = { getSync: (k,d) => values.has(k) ? values.get(k) : d, deleteSync: k => values.delete(k), putSync: (k,v) => values.set(k,v), flush: async () => { flushes++; } };
  const deps = { '@kit.ArkData': { preferences: { getPreferencesSync: () => prefs } }, '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } }, '@kit.BackgroundTasksKit': { reminderAgentManager: { async cancelAllReminders() { calls++; if(fail) throw Error('device'); }, async getValidReminders() { return remaining; } } } };
  const ctx = {exports: {}, require: k => deps[k] || {}};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText, ctx);
  return { run: () => ctx.exports.retireLegacyReminders({}), values, calls: () => calls, flushes: () => flushes, recover: () => {fail = false; remaining = [];} };
}
(async () => {
  const success = fixture(); await success.run(); await success.run();
  assert.equal(success.calls(), 1); assert.equal(success.flushes(), 1);
  assert.equal(success.values.has('reminder_enabled'), false); assert.equal(success.values.get('unrelated'), 'keep');
  for (const f of [fixture(true), fixture(false, [{}])]) {
    await f.run(); assert.equal(f.values.has('reminders_retired_v1'), false); assert.equal(f.values.get('reminder_enabled'), true);
    f.recover(); await f.run(); assert.equal(f.calls(), 2); assert.equal(f.values.get('reminders_retired_v1'), true);
  }
  assert.ok(!source.includes('publishReminder')); assert.ok(!source.includes('requestEnableNotification'));
  assert.ok(!fs.readFileSync('entry/src/main/module.json5','utf8').includes('PUBLISH_AGENT_REMINDER'));
  console.log('PASS: retirement once, app reminder verification, retry on failure/residual reminders, preserve unrelated settings, no publishing or notification permission');
})().catch(e => { console.error(e); process.exitCode = 1; });
