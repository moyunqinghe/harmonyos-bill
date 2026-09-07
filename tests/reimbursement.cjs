// Run: node tests/reimbursement.cjs (Node 22+; uses DevEco's bundled compiler).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.BILL_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const source = fs.readFileSync('entry/src/main/ets/common/BillStore.ets', 'utf8');
class Predicates {
  constructor(table) { this.table = table; this.column = ''; this.value = undefined; }
  equalTo(column, value) { this.column = column; this.value = value; }
  orderByDesc() {}
}
function result(rows) {
  let index = -1;
  return { goToNextRow: () => ++index < rows.length,
    goToFirstRow: () => { index = 0; return rows.length > 0; },
    getString: i => Object.values(rows[index])[i], getLong: i => Object.values(rows[index])[i],
    getDouble: i => Object.values(rows[index])[i], isColumnNull: i => Object.values(rows[index])[i] == null,
    close() {} };
}
function adapter(db) {
  return {
    failReimbursement: false,
    failDetails: false,
    async executeSql(sql) { db.exec(sql); },
    async querySql(sql) { return result(db.prepare(sql).all()); },
    async query(p, columns) { return result(db.prepare(`SELECT ${columns.join(',')} FROM ${p.table} WHERE ${p.column} = ?`).all(p.value)); },
    async insert(table, bucket) {
      if (table === 'bill_reimbursements' && this.failReimbursement) throw new Error('Injected write failure');
      if (table === 'bill_details' && this.failDetails) throw new Error('Injected details failure');
      const keys = Object.keys(bucket);
      return Number(db.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`).run(...Object.values(bucket)).lastInsertRowid);
    },
    async update(bucket, p) { return db.prepare(`UPDATE ${p.table} SET ${Object.keys(bucket).map(k => k + '=?').join(',')} WHERE ${p.column}=?`).run(...Object.values(bucket), p.value).changes; },
    async delete(p) { return p.column ? db.prepare(`DELETE FROM ${p.table} WHERE ${p.column}=?`).run(p.value).changes : db.prepare(`DELETE FROM ${p.table}`).run().changes; },
    beginTransaction() { db.exec('BEGIN'); }, commit() { db.exec('COMMIT'); }, rollBack() { db.exec('ROLLBACK'); }
  };
}
function load(store) {
  const context = { exports: {}, require(name) {
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates, SecurityLevel: {S1:1}, getRdbStore: async () => store } };
    return {fileIo: {unlinkSync() {}}};
  }};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText, context);
  return context.exports.BillStore;
}
(async () => {
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE bills (id INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT NOT NULL,amount REAL NOT NULL,note TEXT NOT NULL DEFAULT '',date TEXT NOT NULL,image TEXT NOT NULL DEFAULT '')");
  db.exec("INSERT INTO bills VALUES(7,'expense',100,'话费','2026-08-26','/sandbox/receipt.jpg')");
  const old = JSON.stringify(db.prepare('SELECT * FROM bills').all());
  const store = adapter(db), BillStore = load(store);
  await Promise.all([BillStore.getStore({}), BillStore.getStore({})]);
  assert.equal(JSON.stringify(db.prepare('SELECT * FROM bills').all()),old,'upgrade preserves all old fields');
  let [bill] = await BillStore.queryAll({});
  assert.equal(bill.category,''); assert.equal(bill.paymentMethod,'');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM bill_details').get().n,0,'old rows are not auto-classified');
  assert.equal(BillStore.personalExpense(bill),100);
  bill.reimbursable = true;
  await BillStore.update({},bill);
  assert.equal(BillStore.reimbursementLabel(bill),'待报销');
  bill.reimbursed = 80; bill.reimbursedDate = '2026-09-05';
  await BillStore.update({},bill); await BillStore.update({},bill);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM bill_reimbursements').get().n,1);
  [bill] = await BillStore.queryAll({});
  assert.equal(BillStore.personalExpense(bill),20,'partial reimbursement deducts once');
  assert.equal(bill.date,'2026-08-26'); assert.equal(bill.reimbursedDate,'2026-09-05');
  bill.reimbursementClosed = true; await BillStore.update({},bill);
  assert.match(BillStore.reimbursementLabel(bill),/报销已结束/);
  await assert.rejects(BillStore.update({}, {...bill, reimbursed:101}));
  await assert.rejects(BillStore.update({}, {...bill, type:'income'}));
  await assert.rejects(BillStore.update({}, {...bill, reimbursedDate:'2026-08-01'}));
  store.failReimbursement=true;
  await assert.rejects(BillStore.update({}, {...bill,note:'should rollback',reimbursed:90}));
  assert.equal(db.prepare('SELECT note FROM bills WHERE id=7').get().note,'话费');
  assert.equal(db.prepare('SELECT received FROM bill_reimbursements WHERE bill_id=7').get().received,80);
  store.failReimbursement=false;
  bill.reimbursed=100; await BillStore.update({},bill);
  const reopened=load(store); [bill] = await reopened.queryAll({});
  assert.equal(reopened.personalExpense(bill),0,'persists after reopening');
  await reopened.add({}, {id:0,type:'repayment',amount:100,note:'还款',date:'2026-09-05',image:''});
  await reopened.add({}, {id:0,type:'income',amount:8000,note:'工资',date:'2026-09-01',image:''});
  await reopened.add({}, {id:0,type:'expense',amount:30,note:'午餐',date:'2026-09-05',image:''});
  function logic(name, currentStore) {
    const context={exports:{},require:()=>({BillStore:currentStore})};
    vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/common/'+name+'.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
    return context.exports[name];
  }
  const Report=logic('MonthlyReport',reopened), Presentation=logic('LedgerPresentation',reopened);
  let report=Report.create(await reopened.queryAll({}),'2026-09');
  assert.equal(report.personal,3000);assert.equal(report.income,800000);assert.equal(report.daily[4],3000);
  assert.equal(Report.create(await reopened.queryAll({}),'2026-08').personal,0);
  const index=fs.readFileSync('entry/src/main/ets/pages/Index.ets','utf8');
  const indexBody=index.split('  async load(): Promise<void> {')[1].split('  money(')[0];
  const indexEnv={BillStore:reopened,MonthlyReport:Report,LedgerPresentation:Presentation,getContext:()=>({})};
  vm.runInNewContext(ts.transpileModule('async function load() {'+indexBody,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,indexEnv);
  const home={loadVersion:0,reportMonth:'2026-08',filter:'待报销',currentMonth:()=> '2026-09'};
  await indexEnv.load.call(home);assert.equal(home.home.personal,3000);assert.equal(home.home.gross,3000);assert.equal(home.home.income,800000);assert.equal(home.report.personal,0);assert.equal(home.filter,'待报销');
  assert.equal(home.groups.length,0,'full settlement leaves pending filter');
  bill.reimbursed=80;bill.reimbursementClosed=false;await reopened.update({},bill);
  await indexEnv.load.call(home);assert.equal(home.pendingCount,1);assert.equal(home.pendingCents,2000);
  assert.equal(home.groups.length,1);assert.equal(home.groups[0].items[0].id,7);assert.equal(home.groups[0].summary,'-¥20.00');
  assert.equal(Presentation.groups(await reopened.queryAll({}),'还款／转账')[0].items[0].type,'repayment');
  await reopened.remove({},7); assert.equal(db.prepare('SELECT COUNT(*) AS n FROM bill_reimbursements').get().n,0);
  // Optional button metadata survives migration, reimbursement, reopening and export.
  const metadataDb=new DatabaseSync(':memory:'); const metadataAdapter=adapter(metadataDb); const metadataStore=load(metadataAdapter);
  for (const paymentMethod of ['零钱','信用卡','花呗','白条','美团月付','抖音月付']) {
    await metadataStore.add({}, {id:0,type:'expense',amount:100,note:'',date:'2026-09-06',image:'',category:'话费',paymentMethod,reimbursable:true});
  }
  let metadata=(await metadataStore.queryAll({}))[0];
  assert.equal(metadata.category,'话费'); assert.equal(metadata.paymentMethod,'抖音月付');
  assert.equal(metadataStore.displayTitle(metadata),'话费');
  metadata.reimbursed=100;metadata.reimbursedDate='2026-09-06';metadata.reimbursementClosed=true;
  await metadataStore.update({},metadata);
  const afterReopen=load(metadataAdapter); metadata=(await afterReopen.queryAll({}))[0];
  assert.equal(metadata.paymentMethod,'抖音月付');assert.equal(afterReopen.personalExpense(metadata),0);
  const csv=afterReopen.csvContent(await afterReopen.queryAll({}));
  assert.ok(csv.startsWith('\uFEFF日期,类型,'));assert.ok(csv.includes('消费场景,支付方式'));
  for (const paymentMethod of ['零钱','信用卡','花呗','白条','美团月付','抖音月付']) assert.ok(csv.includes('"话费","'+paymentMethod+'"'));
  metadataAdapter.failDetails=true;
  await assert.rejects(afterReopen.update({}, {...metadata,category:'购物',note:'must rollback'}));
  metadata=(await afterReopen.queryAll({}))[0];assert.equal(metadata.category,'话费');assert.equal(metadata.note,'');assert.equal(metadata.reimbursed,100);
  const countBefore=(await afterReopen.queryAll({})).length;
  await assert.rejects(afterReopen.add({}, {...metadata,id:0}));
  assert.equal((await afterReopen.queryAll({})).length,countBefore);
  metadataAdapter.failDetails=false;
  await afterReopen.update({}, {...metadata,type:'repayment',reimbursable:false,reimbursed:0});
  metadata=(await afterReopen.queryAll({}))[0];assert.equal(metadata.category,'');assert.equal(metadata.paymentMethod,'');assert.equal(afterReopen.personalExpense(metadata),0);
  await afterReopen.remove({},metadata.id);assert.equal(metadataDb.prepare('SELECT COUNT(*) AS n FROM bill_details WHERE bill_id=?').get(metadata.id).n,0);
  console.log('PASS: optional category/payment buttons persist, reimbursement retains metadata, CSV contains every payment, atomic add/update rollback and type-change cleanup');
  // Replay the user's complete spending timeline against actual store + aggregation code.
  const scenarioDb=new DatabaseSync(':memory:'); const scenarioStore=load(adapter(scenarioDb));
  const entries=[
    ['expense',500,'信用卡衣服','2026-08-26'], ['expense',100,'待报销话费','2026-08-26'],
    ['repayment',600,'还信用卡','2026-09-05'], ['transfer',1000,'自己账户转账','2026-09-05'],
    ['expense',30,'微信零钱午饭','2026-09-06'], ['expense',200,'信用卡消费','2026-09-06'],
    ['expense',70,'花呗日用品','2026-09-06'], ['income',8000,'工资','2026-09-01']
  ];
  for (const [type,amount,note,date] of entries) await scenarioStore.add({}, {id:0,type,amount,note,date,image:'',reimbursable:note==='待报销话费'});
  const scenarioReport=logic('MonthlyReport',scenarioStore);
  async function totals(month) { const st=scenarioReport.create(await scenarioStore.queryAll({}),month); return {expenseTotal:st.personal/100,incomeTotal:st.income/100}; }
  assert.equal((await totals('2026-08')).expenseTotal,600);
  assert.equal((await totals('2026-09')).expenseTotal,300);
  assert.equal((await totals('2026-09')).incomeTotal,8000);
  let phone=(await scenarioStore.queryAll({})).find(b=>b.note==='待报销话费');
  phone.reimbursed=80;phone.reimbursedDate='2026-09-06';await scenarioStore.update({},phone);
  assert.equal((await totals('2026-08')).expenseTotal,520);
  assert.equal((await totals('2026-09')).expenseTotal,300);
  phone.reimbursed=100;await scenarioStore.update({},phone);await scenarioStore.update({},phone);
  assert.equal((await totals('2026-08')).expenseTotal,500);
  assert.equal((await totals('2026-09')).incomeTotal,8000);
  await scenarioStore.add({}, {id:0,type:'expense',amount:120,note:'出差打车',date:'2026-09-06',image:'',reimbursable:true,reimbursed:80,reimbursedDate:'2026-09-06',reimbursementClosed:true});
  assert.equal((await totals('2026-09')).expenseTotal,340);
  phone.reimbursed=80;await scenarioStore.update({},phone);assert.equal((await totals('2026-08')).expenseTotal,520);
  phone.reimbursed=100;await scenarioStore.update({},phone);
  await assert.rejects(scenarioStore.update({}, {...phone,amount:99}));
  const taxi=(await scenarioStore.queryAll({})).find(b=>b.note==='出差打车');await scenarioStore.remove({},taxi.id);
  assert.equal((await totals('2026-09')).expenseTotal,300);
  console.log('PASS: scenario timeline — August 600 → 520 → 500; September 300 → 340 → 300; salary remains 8000; repayment and transfer never inflate spending');
  const early=new DatabaseSync(':memory:');early.exec("CREATE TABLE bills(id INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT,amount REAL,note TEXT,date TEXT); INSERT INTO bills VALUES(1,'expense',5,'旧记录','2025-12-31')");
  const legacy=load(adapter(early));const [legacyBill]=await legacy.queryAll({});assert.equal(legacyBill.amount,5);assert.equal(legacyBill.image,'');
  console.log('PASS: old-data upgrades, concurrent open, pending/partial/full settlement, repeated save, validation, transaction rollback, restart persistence, cross-month statistics, repayment exclusion, receipt preservation and linked cleanup');
})().catch(e=>{console.error(e);process.exitCode=1;});
