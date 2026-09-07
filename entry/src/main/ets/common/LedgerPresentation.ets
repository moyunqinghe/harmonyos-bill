import { Bill, BillStore } from './BillStore';

export interface LedgerGroup { date: string; summary: string; items: Bill[]; }

export class LedgerPresentation {
  static isPending(bill: Bill): boolean {
    return bill.type === 'expense' && !!bill.reimbursable && !bill.reimbursementClosed && (bill.reimbursed ?? 0) < bill.amount;
  }

  static groups(bills: Bill[], filter: string): LedgerGroup[] {
    const map = new Map<string, Bill[]>();
    bills.forEach((bill: Bill) => {
      if (filter === '待报销' && !LedgerPresentation.isPending(bill)) { return; }
      if (filter === '支出' && bill.type !== 'expense') { return; }
      if (filter === '收入' && bill.type !== 'income') { return; }
      if (filter === '还款／转账' && !BillStore.isNeutral(bill.type)) { return; }
      const items = map.get(bill.date) ?? [];
      items.push(bill); map.set(bill.date, items);
    });
    const groups: LedgerGroup[] = [];
    map.forEach((items: Bill[], date: string) => {
      let income = 0;
      let expense = 0;
      items.forEach((bill: Bill) => {
        if (bill.type === 'income') { income += Math.round(bill.amount * 100); }
        expense += Math.round(BillStore.personalExpense(bill) * 100);
      });
      const parts: string[] = [];
      if (income > 0) { parts.push('+¥' + (income / 100).toFixed(2)); }
      if (expense > 0) { parts.push('-¥' + (expense / 100).toFixed(2)); }
      groups.push({ date: date, summary: parts.join('  '), items: items });
    });
    return groups;
  }
}
