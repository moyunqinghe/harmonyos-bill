import { relationalStore, ValuesBucket } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface Bill {
  id: number;
  type: string; // 'income' | 'expense'
  amount: number;
  note: string;
  date: string; // yyyy-MM-dd
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
  'date TEXT NOT NULL)';

export class BillStore {
  private static store?: relationalStore.RdbStore;

  static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (!BillStore.store) {
      BillStore.store = await relationalStore.getRdbStore(context, STORE_CONFIG);
      await BillStore.store.executeSql(CREATE_SQL);
    }
    return BillStore.store;
  }

  static async add(context: common.Context, bill: Bill): Promise<void> {
    const store = await BillStore.getStore(context);
    const bucket: ValuesBucket = {
      type: bill.type,
      amount: bill.amount,
      note: bill.note,
      date: bill.date
    };
    await store.insert('bills', bucket);
  }

  static async remove(context: common.Context, id: number): Promise<void> {
    const store = await BillStore.getStore(context);
    const predicates = new relationalStore.RdbPredicates('bills');
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  static async queryAll(context: common.Context): Promise<Bill[]> {
    const store = await BillStore.getStore(context);
    const predicates = new relationalStore.RdbPredicates('bills');
    predicates.orderByDesc('date');
    predicates.orderByDesc('id');
    const result = await store.query(predicates, ['id', 'type', 'amount', 'note', 'date']);
    const bills: Bill[] = [];
    while (result.goToNextRow()) {
      bills.push({
        id: result.getLong(0),
        type: result.getString(1),
        amount: result.getDouble(2),
        note: result.getString(3),
        date: result.getString(4)
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
        await BillStore.add(context, { id: 0, type: 'expense', amount: rand(t[1], t[2]), note: t[0], date: fmtD(day) });
      }
      if (Math.random() < 0.3) {
        const t = occasional[Math.floor(Math.random() * occasional.length)];
        await BillStore.add(context, { id: 0, type: 'expense', amount: rand(t[1], t[2]), note: t[0], date: fmtD(day) });
      }
    }

    await BillStore.add(context, { id: 0, type: 'income', amount: 8000, note: '工资', date: fmtD(1) });
    if (today >= 15) {
      await BillStore.add(context, { id: 0, type: 'income', amount: 2000, note: '奖金', date: fmtD(15) });
    }
  }
}
