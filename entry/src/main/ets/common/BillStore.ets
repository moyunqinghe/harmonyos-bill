import { relationalStore, ValuesBucket } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export interface Bill {
  id: number;
  type: string; // 'income' | 'expense' | 'repayment' | 'transfer'
  amount: number;
  note: string;
  date: string; // yyyy-MM-dd
  image: string; // 沙盒内图片路径，空串表示无
  category?: string;
  paymentMethod?: string;
  reimbursable?: boolean;
  reimbursed?: number;
  reimbursedDate?: string;
  reimbursementClosed?: boolean;
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'bill.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_SQL = 'CREATE TABLE IF NOT EXISTS bills (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'type TEXT NOT NULL, ' +
  'amount REAL NOT NULL, ' +
  'note TEXT NOT NULL DEFAULT \'\', ' +
  'date TEXT NOT NULL, ' +
  'image TEXT NOT NULL DEFAULT \'\')';

export class BillStore {
  static readonly categories: string[] = ['购物', '交通', '餐饮', '话费', '居住缴费', '休闲娱乐', '医疗健康', '人情往来', '其他'];
  static readonly paymentMethods: string[] = ['零钱', '信用卡', '花呗', '白条', '美团月付', '抖音月付'];

  static displayTitle(bill: Bill): string {
    return bill.note.length > 0 ? bill.note : (bill.type === 'expense' && bill.category ? bill.category : BillStore.typeLabel(bill.type));
  }

  static detailLabel(bill: Bill): string {
    const parts: string[] = [BillStore.typeLabel(bill.type)];
    if (bill.type === 'expense') {
      if (bill.category) { parts.push(bill.category); }
      if (bill.paymentMethod) { parts.push(bill.paymentMethod); }
      if (bill.reimbursable) { parts.push(BillStore.reimbursementLabel(bill)); }
    } else if (BillStore.isNeutral(bill.type)) { parts.push('不计收支'); }
    return parts.join(' · ');
  }

  static csvContent(bills: Bill[]): string {
    const esc = (t: string): string => '"' + t.replace(/"/g, '""') + '"';
    const lines: string[] = ['日期,类型,金额(元),备注,报销状态,累计已报销(元),最近到账日期,个人花销(元),消费场景,支付方式'];
    bills.forEach((b: Bill) => {
      lines.push([b.date, BillStore.typeLabel(b.type), b.amount.toFixed(2), esc(b.note),
        esc(BillStore.reimbursementLabel(b)), (b.reimbursed ?? 0).toFixed(2),
        b.reimbursedDate ?? '', BillStore.personalExpense(b).toFixed(2),
        esc(b.type === 'expense' ? (b.category || '未选择') : ''),
        esc(b.type === 'expense' ? (b.paymentMethod || '未选择') : '')].join(','));
    });
    return '\uFEFF' + lines.join('\r\n');
  }

  private static store?: relationalStore.RdbStore;
  private static opening?: Promise<relationalStore.RdbStore>;

  static personalExpense(bill: Bill): number {
    if (bill.type !== 'expense') { return 0; }
    return Math.max(0, Math.round((bill.amount - (bill.reimbursed ?? 0)) * 100) / 100);
  }

  static reimbursementLabel(bill: Bill): string {
    if (bill.type !== 'expense' || !bill.reimbursable) { return ''; }
    const received = bill.reimbursed ?? 0;
    if (received >= bill.amount) { return '已全额报销'; }
    if (bill.reimbursementClosed) { return '报销已结束 · 自付 ¥' + BillStore.personalExpense(bill).toFixed(2); }
    return received > 0 ? '部分报销 · 已到账 ¥' + received.toFixed(2) : '待报销';
  }

  static isNeutral(type: string): boolean {
    return type === 'repayment' || type === 'transfer';
  }

  static typeLabel(type: string): string {
    if (type === 'income') { return '收入'; }
    if (type === 'expense') { return '支出'; }
    if (type === 'repayment') { return '还款'; }
    if (type === 'transfer') { return '转账'; }
    return '其他';
  }

  static amountPrefix(type: string): string {
    if (type === 'income') { return '+'; }
    if (type === 'expense') { return '-'; }
    return '';
  }

  static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (BillStore.store) { return BillStore.store; }
    if (!BillStore.opening) {
      BillStore.opening = BillStore.openStore(context);
    }
    try {
      BillStore.store = await BillStore.opening;
      return BillStore.store;
    } finally {
      BillStore.opening = undefined;
    }
  }

  private static async openStore(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await store.executeSql(CREATE_SQL);
    // 兼容未带图片列的早期版本；不重建或改写已有账单。
    const columns = await store.querySql('PRAGMA table_info(bills)');
    let hasImage = false;
    while (columns.goToNextRow()) {
      if (columns.getString(1) === 'image') { hasImage = true; }
    }
    columns.close();
    if (!hasImage) {
      await store.executeSql("ALTER TABLE bills ADD COLUMN image TEXT NOT NULL DEFAULT ''");
    }
    await store.executeSql('CREATE TABLE IF NOT EXISTS bill_reimbursements (' +
      'bill_id INTEGER PRIMARY KEY, received REAL NOT NULL DEFAULT 0, ' +
      "received_date TEXT NOT NULL DEFAULT '', closed INTEGER NOT NULL DEFAULT 0)");
    await store.executeSql('CREATE TABLE IF NOT EXISTS bill_details (' +
      "bill_id INTEGER PRIMARY KEY, category TEXT NOT NULL DEFAULT '', payment_method TEXT NOT NULL DEFAULT '')");
    return store;
  }

  private static async writeDetails(store: relationalStore.RdbStore, id: number, bill: Bill): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('bill_details');
    predicates.equalTo('bill_id', id);
    await store.delete(predicates);
    if (bill.type === 'expense' && (bill.category || bill.paymentMethod)) {
      await store.insert('bill_details', {
        bill_id: id, category: bill.category ?? '', payment_method: bill.paymentMethod ?? ''
      });
    }
  }

  private static async writeReimbursement(store: relationalStore.RdbStore, id: number, bill: Bill): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('bill_reimbursements');
    predicates.equalTo('bill_id', id);
    await store.delete(predicates);
    if (bill.type === 'expense' && bill.reimbursable) {
      await store.insert('bill_reimbursements', {
        bill_id: id, received: bill.reimbursed ?? 0,
        received_date: bill.reimbursedDate ?? '', closed: bill.reimbursementClosed ? 1 : 0
      });
    }
  }

  static validateReimbursement(bill: Bill): void {
    const received = bill.reimbursed ?? 0;
    if (!Number.isFinite(bill.amount) || bill.amount <= 0 || !Number.isFinite(received) || received < 0 || received > bill.amount) {
      throw new Error('报销金额不能超过消费金额');
    }
    if (received > 0 && (bill.type !== 'expense' || !bill.reimbursable || !bill.reimbursedDate || bill.reimbursedDate < bill.date)) {
      throw new Error('请检查报销状态和到账日期');
    }
  }

  static async add(context: common.Context, bill: Bill): Promise<void> {
    const store = await BillStore.getStore(context);
    const bucket: ValuesBucket = {
      type: bill.type,
      amount: bill.amount,
      note: bill.note,
      date: bill.date,
      image: bill.image
    };
    BillStore.validateReimbursement(bill);
    store.beginTransaction();
    try {
      const id = await store.insert('bills', bucket);
      await BillStore.writeReimbursement(store, id, bill);
      await BillStore.writeDetails(store, id, bill);
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new Error('账本保存失败');
    }
  }

  static async remove(context: common.Context, id: number): Promise<void> {
    const store = await BillStore.getStore(context);
    const predicates = new relationalStore.RdbPredicates('bills');
    predicates.equalTo('id', id);
    // 先查出关联图片，删记录后一并清理沙盒文件
    const result = await store.query(predicates, ['image']);
    let image = '';
    if (result.goToFirstRow()) {
      image = result.getString(0);
    }
    result.close();
    store.beginTransaction();
    try {
      const reimbursement = new relationalStore.RdbPredicates('bill_reimbursements');
      reimbursement.equalTo('bill_id', id);
      await store.delete(reimbursement);
      const details = new relationalStore.RdbPredicates('bill_details');
      details.equalTo('bill_id', id);
      await store.delete(details);
      await store.delete(predicates);
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new Error('账本保存失败');
    }
    if (image.length > 0) {
      try {
        fileIo.unlinkSync(image);
      } catch (e) {
        // 文件不存在或已删除，忽略
      }
    }
  }

  static async update(context: common.Context, bill: Bill): Promise<void> {
    const store = await BillStore.getStore(context);
    const bucket: ValuesBucket = {
      type: bill.type,
      amount: bill.amount,
      note: bill.note,
      date: bill.date,
      image: bill.image
    };
    const predicates = new relationalStore.RdbPredicates('bills');
    predicates.equalTo('id', bill.id);
    BillStore.validateReimbursement(bill);
    store.beginTransaction();
    try {
      await store.update(bucket, predicates);
      await BillStore.writeReimbursement(store, bill.id, bill);
      await BillStore.writeDetails(store, bill.id, bill);
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new Error('账本保存失败');
    }
  }

  static async queryAll(context: common.Context): Promise<Bill[]> {
    const store = await BillStore.getStore(context);
    const predicates = new relationalStore.RdbPredicates('bills');
    predicates.orderByDesc('date');
    predicates.orderByDesc('id');
    const result = await store.querySql('SELECT b.id, b.type, b.amount, b.note, b.date, b.image, ' +
      'r.bill_id, r.received, r.received_date, r.closed, d.category, d.payment_method FROM bills b ' +
      'LEFT JOIN bill_reimbursements r ON b.id = r.bill_id ' +
      'LEFT JOIN bill_details d ON b.id = d.bill_id ORDER BY b.date DESC, b.id DESC');
    const bills: Bill[] = [];
    while (result.goToNextRow()) {
      bills.push({
        id: result.getLong(0),
        type: result.getString(1),
        amount: result.getDouble(2),
        note: result.getString(3),
        date: result.getString(4),
        image: result.getString(5),
        reimbursable: !result.isColumnNull(6),
        reimbursed: result.isColumnNull(7) ? 0 : result.getDouble(7),
        reimbursedDate: result.isColumnNull(8) ? '' : result.getString(8),
        reimbursementClosed: !result.isColumnNull(9) && result.getLong(9) === 1,
        category: result.isColumnNull(10) ? '' : result.getString(10),
        paymentMethod: result.isColumnNull(11) ? '' : result.getString(11)
      });
    }
    result.close();
    return bills;
  }

  static async clearAll(context: common.Context): Promise<void> {
    const store = await BillStore.getStore(context);
    const predicates = new relationalStore.RdbPredicates('bills');
    await store.delete(predicates);
  }

  /** 临时调试用：生成上个月整月的模拟数据（日常小额 + 偶发大额 + 工资/奖金） */
  static async seedMock(context: common.Context): Promise<void> {
    // 取上个月（跨年时 1 月回退到上年 12 月）
    const prev = new Date();
    prev.setDate(1);
    prev.setMonth(prev.getMonth() - 1);
    const year = prev.getFullYear();
    const month = prev.getMonth();
    const today = new Date(year, month + 1, 0).getDate();
    const fmtD = (day: number): string =>
      `${year}-${(month + 1).toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
    const rand = (min: number, max: number): number =>
      Math.round((min + Math.random() * (max - min)) * 100) / 100;

    const daily: Array<[string, number, number]> = [
      ['早餐', 5, 15],
      ['午餐', 15, 40],
      ['咖啡', 9, 32],
      ['地铁', 3, 10],
      ['晚餐', 20, 60]
    ];
    const occasional: Array<[string, number, number]> = [
      ['超市采购', 50, 200],
      ['淘宝', 80, 400],
      ['聚餐', 80, 300],
      ['打车', 15, 60],
      ['电影', 30, 80],
      ['水果', 10, 50],
      ['话费', 50, 100]
    ];

    for (let day = 1; day <= today; day++) {
      const n = 1 + Math.floor(Math.random() * 3);
      for (let k = 0; k < n; k++) {
        if (Math.random() < 0.18) {
          continue;
        }
        const t = daily[Math.floor(Math.random() * daily.length)];
        await BillStore.add(context, { id: 0, type: 'expense', amount: rand(t[1], t[2]), note: t[0], date: fmtD(day), image: '' });
      }
      if (Math.random() < 0.3) {
        const t = occasional[Math.floor(Math.random() * occasional.length)];
        await BillStore.add(context, { id: 0, type: 'expense', amount: rand(t[1], t[2]), note: t[0], date: fmtD(day), image: '' });
      }
    }

    await BillStore.add(context, { id: 0, type: 'income', amount: 8000, note: '工资', date: fmtD(1), image: '' });
    if (today >= 15) {
      await BillStore.add(context, { id: 0, type: 'income', amount: 2000, note: '奖金', date: fmtD(15), image: '' });
    }
  }
}
