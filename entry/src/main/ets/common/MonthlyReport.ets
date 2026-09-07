import { Bill, BillStore } from './BillStore';

export interface ReportGroup { label: string; cents: number; }
export interface ReportData {
  month: string;
  bills: Bill[];
  income: number;
  gross: number;
  received: number;
  personal: number;
  pending: number;
  repayment: number;
  transfer: number;
  categories: ReportGroup[];
  payments: ReportGroup[];
  daily: number[];
}

export class MonthlyReport {
  static create(bills: Bill[], month: string): ReportData {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) { throw new Error('月份无效'); }
    const parts = month.split('-');
    const data: ReportData = { month: month, bills: bills.filter((b: Bill) => b.date.startsWith(month + '-')),
      income: 0, gross: 0, received: 0, personal: 0, pending: 0, repayment: 0, transfer: 0,
      categories: [], payments: [], daily: new Array<number>(new Date(Number(parts[0]), Number(parts[1]), 0).getDate()).fill(0) };
    const categories = new Map<string, number>();
    const payments = new Map<string, number>();
    data.bills.forEach((b: Bill) => {
      const amount = Math.round(b.amount * 100);
      if (b.type === 'income') { data.income += amount; }
      if (b.type === 'repayment') { data.repayment += amount; }
      if (b.type === 'transfer') { data.transfer += amount; }
      if (b.type !== 'expense') { return; }
      const personal = Math.round(BillStore.personalExpense(b) * 100);
      data.gross += amount;
      data.personal += personal;
      data.received += amount - personal;
      if (b.reimbursable && !b.reimbursementClosed) { data.pending += personal; }
      const category = b.category || '未选择';
      const payment = b.paymentMethod || '未选择';
      categories.set(category, (categories.get(category) ?? 0) + personal);
      payments.set(payment, (payments.get(payment) ?? 0) + amount);
      const day = Number(b.date.substring(8, 10));
      if (day >= 1 && day <= data.daily.length) { data.daily[day - 1] += personal; }
    });
    categories.forEach((cents: number, label: string) => data.categories.push({ label: label, cents: cents }));
    payments.forEach((cents: number, label: string) => data.payments.push({ label: label, cents: cents }));
    data.categories.sort((a: ReportGroup, b: ReportGroup) => b.cents - a.cents);
    data.payments.sort((a: ReportGroup, b: ReportGroup) => b.cents - a.cents);
    return data;
  }

  static escape(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  static money(cents: number): string { return '¥' + (cents / 100).toFixed(2); }

  static groupColors(label: string, payment: boolean = false): string[] {
    const labels = payment ? BillStore.paymentMethods : BillStore.categories;
    const index = labels.indexOf(label);
    const colors: string[] = payment
      ? ['#b9eadb, #8ed1c3', '#c6ddfa, #a4c4ef', '#ffe1b7, #f5c991', '#ddd1f7, #c5b4ec', '#f9d2df, #edb1c9', '#f7edb7, #e8d78f']
      : ['#c6ddfa, #a4c4ef', '#ddd1f7, #c5b4ec', '#ffe1b7, #f5c991', '#b9eadb, #8ed1c3', '#f7edb7, #e8d78f', '#cdd6fa, #b3bdec', '#d9edc4, #bbd99d', '#f9d6cc, #edb4a4', '#f9d2df, #edb1c9'];
    return (index >= 0 ? colors[index] : '#e2e7ee, #c7d0dc').split(', ');
  }

  private static barGradient(label: string, payment: boolean): string {
    return 'linear-gradient(90deg, ' + MonthlyReport.groupColors(label, payment).join(', ') + ')';
  }

  private static bars(groups: ReportGroup[], total: number, payment: boolean): string {
    if (groups.length === 0) { return '<p class="muted">本月没有消费记录</p>'; }
    return groups.map((g: ReportGroup) => {
      const gradient = MonthlyReport.barGradient(g.label, payment);
      const percent = total > 0 ? g.cents / total * 100 : 0;
      return `<div class="bar-row"><div class="bar-label"><span class="category-name"><i class="swatch" style="background:${gradient}"></i>${MonthlyReport.escape(g.label)}</span><span>${MonthlyReport.money(g.cents)} <small>${percent.toFixed(1)}%</small></span></div><div class="track"><div style="width:${percent.toFixed(3)}%;background:${gradient}"></div></div></div>`;
    }).join('');
  }

  private static dailyChart(daily: number[]): string {
    const max = Math.max(1, ...daily);
    const step = 660 / daily.length;
    let content = '';
    daily.forEach((cents: number, i: number) => {
      const height = cents / max * 100;
      content += `<rect x="${40 + i * step}" y="${122 - height}" width="${Math.max(2, step - 4)}" height="${height}" rx="2" fill="#0d9488"><title>${i + 1}日 ${MonthlyReport.money(cents)}</title></rect>`;
      if (i % 5 === 0 || i === daily.length - 1) { content += `<text x="${40 + i * step}" y="143">${i + 1}</text>`; }
    });
    return `<svg viewBox="0 0 710 150" role="img" aria-label="每日个人花销，单位元"><text x="0" y="16">${(Math.max(...daily) / 100).toFixed(2)}</text><text x="18" y="124">0</text><path d="M38 22V123H702" stroke="#d7e1df" fill="none"/>${content}</svg>`;
  }

  static html(data: ReportData): string {
    const esc = MonthlyReport.escape;
    const money = MonthlyReport.money;
    const rows = data.bills.map((b: Bill) => `<tr><td>${esc(b.date.substring(5))}</td><td>${esc(BillStore.typeLabel(b.type))}</td><td>${esc(b.type === 'expense' ? (b.category || '未选择') : '-')}<br><small>${esc(b.paymentMethod || '')}</small></td><td class="note">${esc(b.note || '-')}</td><td>${money(Math.round(b.amount * 100))}</td><td>${esc(BillStore.reimbursementLabel(b) || '-')}<br><small>${b.reimbursable ? '累计 ' + money(Math.round((b.reimbursed ?? 0) * 100)) : ''}</small></td><td>${b.type === 'expense' ? money(Math.round(BillStore.personalExpense(b) * 100)) : '-'}</td></tr>`).join('');
    return `<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><title>Bill ${data.month} 月报</title><style>
      *{box-sizing:border-box}body{margin:0;color:#173c37;background:#eef3f1;font:14px sans-serif;line-height:1.5}main{max-width:820px;margin:auto;background:white;padding:32px}h1{font-size:28px;margin:4px 0 20px}h2{font-size:16px;margin:0 0 12px}p{margin:8px 0}.eyebrow{letter-spacing:2px;color:#53736e;font-size:12px}.hero{background:#0f766e;color:white;padding:22px;border-radius:14px}.hero strong{display:block;font-size:38px;line-height:1.4}.hero small{color:#d1eee6}.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:16px 0}.metric{padding:12px;background:#f2f6f5;border-radius:10px}.metric span{display:block;color:#5b736e;font-size:12px}.metric b{font-size:18px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin:22px 0}.bar-row{margin:10px 0;break-inside:avoid}.bar-label{display:flex;justify-content:space-between;gap:10px;font-size:12px}.category-name{display:flex;align-items:center;gap:6px}.swatch{display:inline-block;width:9px;height:9px;border-radius:3px;flex-shrink:0}.track{height:9px;background:#f1f4f6;border-radius:6px;margin-top:5px;overflow:hidden}.track div{height:100%;border-radius:6px}.muted,small{color:#657d77;font-size:11px}.info{padding:12px;background:#f2f6f5;border-radius:10px;font-size:11px;margin-top:16px}svg{width:100%;display:block}svg text{font:10px sans-serif;fill:#657d77}.details{margin-top:30px}table{width:100%;border-collapse:collapse;font-size:10px;table-layout:fixed}th,td{text-align:left;padding:9px 5px;border-bottom:1px solid #dfe9e6;vertical-align:top;overflow-wrap:anywhere}th{background:#eff5f3}td.note{white-space:pre-wrap}tr{break-inside:avoid}thead{display:table-header-group}.footer{font-size:10px;color:#657d77;margin-top:16px}.empty{text-align:center;padding:30px;color:#657d77}@media(max-width:540px){main{padding:18px}.columns{grid-template-columns:1fr}.metric b{font-size:15px}.hero strong{font-size:32px}table{font-size:9px}}@media print{.bar-row{margin:6px 0}.columns{margin:16px 0}.hero{padding:18px}.metrics{margin:12px 0}h1{margin-bottom:14px}body{background:white}main{max-width:none;padding:0}.columns{grid-template-columns:1fr 1fr}.details{break-before:page;margin-top:0}.overview{break-inside:avoid}.hero,.metric,.track,.track div,.swatch,th{-webkit-print-color-adjust:exact;print-color-adjust:exact}}@page{size:A4;margin:12mm}
      </style></head><body><main><section class="overview"><div class="eyebrow">BILL / MONTHLY REPORT</div><h1>${data.month} 消费月报</h1><div class="hero">个人实际花销<strong>${money(data.personal)}</strong><small>消费 ${money(data.gross)} − 累计已到账报销 ${money(data.received)}</small></div><div class="metrics"><div class="metric"><span>本月收入</span><b>${money(data.income)}</b></div><div class="metric"><span>本月还款 · 不计花销</span><b>${money(data.repayment)}</b></div><div class="metric"><span>本月消费尚待报销</span><b>${money(data.pending)}</b></div></div><div class="columns"><section><h2>钱花在哪</h2><p class="muted">个人花销，扣除已到账报销</p>${MonthlyReport.bars(data.categories, data.personal, false)}</section><section><h2>用什么支付</h2><p class="muted">原消费金额，包含垫付；不是待还金额</p>${MonthlyReport.bars(data.payments, data.gross, true)}</section></div><h2>每日个人花销 <small>单位：元</small></h2>${MonthlyReport.dailyChart(data.daily)}<div class="info">本月转账 ${money(data.transfer)}，单独留记录，不计收支。报销按本月消费关联的累计到账金额冲减原消费月份，不算到账月份收入；本月消费尚待报销不含其他月份垫付。历史月份会随后续报销到账更新。未选择的场景或支付方式单独汇总。</div></section><section class="details"><h2>${data.month} 账单明细 · ${data.bills.length} 笔</h2>${data.bills.length === 0 ? '<p class="empty">这个月还没有记录</p>' : `<table><thead><tr><th style="width:9%">日期</th><th style="width:8%">类型</th><th style="width:14%">场景 / 支付</th><th style="width:20%">备注</th><th style="width:14%">原金额</th><th style="width:21%">报销状态</th><th style="width:14%">个人花销</th></tr></thead><tbody>${rows}</tbody></table>`}<p class="footer">Bill · 导出时的账本快照 · 还款和转账不重复计入消费</p></section></main></body></html>`;
  }
}
