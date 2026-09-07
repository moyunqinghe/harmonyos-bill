const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.BILL_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
function load(path, deps) {
 const context = { exports: {}, require: name => deps[name] || {} };
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path,'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 return context.exports;
}
const store = load('entry/src/main/ets/common/BillStore.ets', {'@kit.ArkData':{relationalStore:{SecurityLevel:{S1:1}}}});
const {MonthlyReport:R} = load('entry/src/main/ets/common/MonthlyReport.ets',{'./BillStore':store});
const bills = [
 {type:'expense',amount:500,category:'购物',paymentMethod:'信用卡',date:'2026-08-26'},
 {type:'expense',amount:100,category:'话费',paymentMethod:'信用卡',date:'2026-08-26',reimbursable:true,reimbursed:100,reimbursedDate:'2026-09-06',reimbursementClosed:true},
 {type:'income',amount:8000,note:'工资',date:'2026-09-01'},
 {type:'expense',amount:30,category:'餐饮',paymentMethod:'零钱',date:'2026-09-02'},
 {type:'expense',amount:200,category:'购物',paymentMethod:'花呗',date:'2026-09-03'},
 {type:'expense',amount:120,category:'交通',paymentMethod:'信用卡',date:'2026-09-04',reimbursable:true,reimbursed:80,reimbursedDate:'2026-09-06',reimbursementClosed:true},
 {type:'expense',amount:50,category:'话费',paymentMethod:'信用卡',date:'2026-09-05',reimbursable:true},
 {type:'expense',amount:5,note:'旧记录 <script>alert(1)</script> & "中文"',date:'2026-09-06'},
 {type:'repayment',amount:600,date:'2026-09-06'},
 {type:'transfer',amount:1000,date:'2026-09-06'}
].map((b,i)=>({id:i+1,note:'',image:'',...b}));
const aug=R.create(bills,'2026-08'), sep=R.create(bills,'2026-09');
assert.equal(aug.personal,50000);assert.equal(aug.received,10000);
assert.equal(sep.personal,32500);assert.equal(sep.gross,40500);assert.equal(sep.received,8000);assert.equal(sep.pending,5000);
assert.equal(sep.income,800000);assert.equal(sep.repayment,60000);assert.equal(sep.transfer,100000);
assert.equal(sep.categories.reduce((s,x)=>s+x.cents,0),sep.personal);
assert.equal(sep.payments.reduce((s,x)=>s+x.cents,0),sep.gross);
assert.equal(sep.daily.reduce((s,x)=>s+x,0),sep.personal);
assert.equal(sep.categories.find(x=>x.label==='未选择').cents,500);
assert.equal(R.create(bills,'2024-02').daily.length,29);
assert.throws(()=>R.create(bills,'2026-99'));
const html=R.html(sep);assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.ok(html.includes('消费月报'));assert.ok(html.includes('不是待还金额'));
const empty=R.html(R.create([],'2026-09'));assert.ok(empty.includes('这个月还没有记录'));assert.ok(!empty.includes('NaN'));assert.ok(!empty.includes('Infinity'));
if (process.env.BILL_REPORT_HTML) {fs.writeFileSync(process.env.BILL_REPORT_HTML,html);}
console.log('PASS: month scope, full/partial/closed reimbursement, repayment exclusion, category/payment/daily reconciliation, missing labels, leap month, empty report and HTML escaping');
