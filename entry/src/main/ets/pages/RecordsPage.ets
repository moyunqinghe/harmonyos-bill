import { router, promptAction, curves } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { Bill, BillStore } from '../common/BillStore';
import { Theme } from '../common/Theme';

interface GroupHeaderParams {
  label: string;
  summary: string;
}

interface DateGroup {
  label: string;
  summary: string;
  items: Bill[];
}

@Entry
@Component
struct RecordsPage {
  @State groups: DateGroup[] = [];

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  static fmtDate(d: Date): string {
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  static dateLabel(date: string): string {
    const today = RecordsPage.fmtDate(new Date());
    const y = new Date();
    y.setDate(y.getDate() - 1);
    if (date === today) {
      return '今天';
    }
    if (date === RecordsPage.fmtDate(y)) {
      return '昨天';
    }
    return date;
  }

  async load(): Promise<void> {
    const bills = await BillStore.queryAll(getContext(this));
    const map = new Map<string, Bill[]>();
    bills.forEach((b: Bill) => {
      const arr = map.get(b.date) ?? [];
      arr.push(b);
      map.set(b.date, arr);
    });
    const groups: DateGroup[] = [];
    map.forEach((items: Bill[], date: string) => {
      let income = 0;
      let expense = 0;
      items.forEach((b: Bill) => {
        if (b.type === 'income') {
          income += b.amount;
        } else {
          expense += b.amount;
        }
      });
      const parts: string[] = [];
      if (income > 0) {
        parts.push('+¥' + income.toFixed(2));
      }
      if (expense > 0) {
        parts.push('-¥' + expense.toFixed(2));
      }
      groups.push({ label: RecordsPage.dateLabel(date), summary: parts.join('  '), items: items });
    });
    this.groups = groups;
  }

  async exportCsv(): Promise<void> {
    const bills = await BillStore.queryAll(getContext(this));
    if (bills.length === 0) {
      promptAction.showToast({ message: '暂无数据可导出' });
      return;
    }
    const esc = (t: string): string => '"' + t.replace(/"/g, '""') + '"';
    const lines: string[] = ['日期,类型,金额(元),备注'];
    bills.forEach((b: Bill) => {
      lines.push([
        b.date,
        b.type === 'income' ? '收入' : '支出',
        b.amount.toFixed(2),
        esc(b.note)
      ].join(','));
    });
    // 带 BOM 的 UTF-8，Excel 打开中文不乱码
    const csv = '\uFEFF' + lines.join('\r\n');
    try {
      const context = getContext(this);
      const docPicker = new picker.DocumentViewPicker(context);
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`bill-${new Date().toISOString().substring(0, 10)}.csv`];
      const uris = await docPicker.save(opts);
      if (!uris || uris.length === 0) {
        return; // 用户取消
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, csv);
      fileIo.closeSync(file);
      promptAction.showToast({ message: `已导出 ${bills.length} 条记录` });
    } catch (e) {
      promptAction.showToast({ message: '导出失败，请重试' });
    }
  }

  confirmDelete(item: Bill): void {
    const desc = item.note.length > 0 ? item.note : (item.type === 'income' ? '收入' : '支出');
    AlertDialog.show({
      title: '删除这条记录？',
      message: `${item.date} ${desc} ¥${item.amount.toFixed(2)}，删除后无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.expense,
        action: async () => {
          await BillStore.remove(getContext(this), item.id);
          this.load();
        }
      }
    });
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.textPrimary)
          .width(40)
          .onClick(() => router.back())
        Blank()
        Text('账单记录')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
        Blank()
        Text('导出')
          .fontSize(15)
          .fontColor(Theme.accent)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.exportCsv();
          })
      }
      .width('100%')
      .padding({ bottom: 14 })

      if (this.groups.length === 0) {
        Column({ space: 10 }) {
          Circle({ width: 56, height: 56 })
            .fill(Theme.card)
          Text('还没有记录')
            .fontSize(15)
            .fontColor(Theme.textSecondary)
          Text('回到首页记一笔吧')
            .fontSize(12)
            .fontColor(Theme.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 18 }) {
          ForEach(this.groups, (g: DateGroup) => {
            ListItemGroup({ header: this.GroupHeader({ label: g.label, summary: g.summary }) }) {
              ForEach(g.items, (item: Bill) => {
                ListItem() {
                  Row() {
                    Circle({ width: 8, height: 8 })
                      .fill(item.type === 'income' ? Theme.income : Theme.expense)
                    Column({ space: 4 }) {
                      Text(item.note.length > 0 ? item.note : (item.type === 'income' ? '收入' : '支出'))
                        .fontSize(15)
                        .fontColor(Theme.textPrimary)
                        .maxLines(1)
                      Text(item.type === 'income' ? '收入' : '支出')
                        .fontSize(11)
                        .fontColor(Theme.textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .margin({ left: 12 })
                    Text((item.type === 'income' ? '+' : '-') + '¥' + item.amount.toFixed(2))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(item.type === 'income' ? Theme.income : Theme.expense)
                  }
                  .width('100%')
                  .padding(14)
                  .margin({ top: 6 })
                  .backgroundColor(Theme.card)
                  .borderRadius(12)
                }
                .transition(TransitionEffect.asymmetric(
                  TransitionEffect.opacity(0)
                    .combine(TransitionEffect.translate({ y: 20 }))
                    .animation({ duration: 320, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) }),
                  TransitionEffect.opacity(0)
                    .combine(TransitionEffect.translate({ x: 80 }))
                    .animation({ duration: 220, curve: Curve.EaseIn })
                ))
                .swipeAction({
                  end: {
                    builder: () => {
                      this.DeleteButton(item)
                    }
                  }
                })
              }, (item: Bill) => item.id.toString())
            }
          }, (g: DateGroup) => g.label)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(Theme.bg)
  }

  @Builder
  GroupHeader(p: GroupHeaderParams) {
    Row() {
      Text(p.label)
        .fontSize(13)
        .fontColor(Theme.textSecondary)
      Blank()
      Text(p.summary)
        .fontSize(12)
        .fontColor(Theme.textSecondary)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  DeleteButton(item: Bill) {
    Text('删除')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(76)
      .height('100%')
      .backgroundColor(Theme.expense)
      .onClick(() => {
        this.confirmDelete(item);
      })
  }
}
