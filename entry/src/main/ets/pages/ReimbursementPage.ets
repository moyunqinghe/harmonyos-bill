import { router, promptAction, KeyboardAvoidMode } from '@kit.ArkUI';
import { Bill, BillStore } from '../common/BillStore';
import { LedgerPresentation } from '../common/LedgerPresentation';
import { Theme } from '../common/Theme';

@Entry
@Component
struct ReimbursementPage {
  @State bill: Bill = { id: 0, type: 'expense', amount: 0, note: '', date: '', image: '' };
  @State received: string = '0';
  @State receivedDate: string = '';
  @State closed: boolean = false;
  @State loaded: boolean = false;
  @State saving: boolean = false;
  @State advanced: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.load();
  }

  async load(): Promise<void> {
    try {
      const params = router.getParams() as Record<string, Object>;
      const bills = await BillStore.queryAll(getContext(this));
      const found = bills.find((b: Bill) => b.id === (params.id as number));
      if (!found || found.type !== 'expense') {
        promptAction.showToast({ message: '找不到可报销的支出' });
        router.back();
        return;
      }
      this.bill = found;
      this.received = (found.reimbursed ?? 0).toString();
      this.closed = found.reimbursementClosed ?? false;
      this.receivedDate = LedgerPresentation.isPending(found) ? this.today() : (found.reimbursedDate || this.today());
      this.loaded = true;
    } catch (e) {
      promptAction.showToast({ message: '加载失败，请返回重试' });
    }
  }

  today(): string {
    const d = new Date();
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
  }

  async save(): Promise<void> {
    if (!this.loaded || this.saving) { return; }
    const received = Number(this.received);
    if (!/^\d+(\.\d{1,2})?$/.test(this.received) || !Number.isFinite(received) || received < 0 || received > this.bill.amount) {
      promptAction.showToast({ message: '请输入 0 到消费金额之间的数字，最多两位小数' });
      return;
    }
    if (received > 0 && (this.receivedDate < this.bill.date || this.receivedDate > this.today())) {
      promptAction.showToast({ message: '到账日期应在消费日期与今天之间' });
      return;
    }
    this.saving = true;
    try {
      const updated: Bill = {
        id: this.bill.id, type: this.bill.type, amount: this.bill.amount,
        note: this.bill.note, date: this.bill.date, image: this.bill.image,
        category: this.bill.category, paymentMethod: this.bill.paymentMethod,
        reimbursable: true, reimbursed: received,
        reimbursedDate: received > 0 ? this.receivedDate : '',
        reimbursementClosed: this.closed || received === this.bill.amount
      };
      await BillStore.update(getContext(this), updated);
      promptAction.showToast({ message: received > 0 ? '已登记，消费月份的个人花销已更新' : '已保存报销状态' });
      router.back();
    } catch (e) {
      promptAction.showToast({ message: '保存失败，请重试' });
    } finally {
      this.saving = false;
    }
  }

  async saveFull(): Promise<void> {
    if (this.saving || !this.loaded) { return; }
    this.received = this.bill.amount.toFixed(2);
    this.closed = true;
    await this.save();
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Row() {
          Text('‹').fontSize(26).fontColor(Theme.textPrimary).width(40)
            .onClick(() => router.back())
          Text('登记报销').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
          Blank()
        }.width('100%')
        if (this.loaded) {
          Column({ space: 10 }) {
            Text(BillStore.displayTitle(this.bill)).fontSize(18).fontColor(Theme.textPrimary)
            Text(this.bill.date + ' · 消费 ¥' + this.bill.amount.toFixed(2))
              .fontSize(14).fontColor(Theme.textSecondary)
          }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
            .backgroundColor(Theme.card).borderRadius(14)

          if (!this.advanced) {
            Column({ space: 12 }) {
              Text('还差多少到账').fontSize(13).fontColor(Theme.textSecondary)
              Text('¥' + Math.max(0, this.bill.amount - (this.bill.reimbursed ?? 0)).toFixed(2))
                .fontSize(38).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
              Text('已到账 ¥' + (this.bill.reimbursed ?? 0).toFixed(2) + ' / 原消费 ¥' + this.bill.amount.toFixed(2))
                .fontSize(13).fontColor(Theme.textSecondary)
            }.width('100%').alignItems(HorizontalAlign.Start).padding(22).borderRadius(22)
              .linearGradient({ angle: 110, colors: [[Theme.incomeCardStart, 0], [Theme.card, 1]] })
          }
          Text(this.advanced ? '返回全额到账 ‹' : '部分到账 / 更正记录 ›')
            .fontSize(14).fontColor(Theme.accent).width('100%').padding({ top: 8, bottom: 8 })
            .onClick(() => {
              this.advanced = !this.advanced;
              this.received = (this.bill.reimbursed ?? 0).toString();
              this.closed = this.bill.reimbursementClosed ?? false;
              this.receivedDate = LedgerPresentation.isPending(this.bill) ? this.today() : (this.bill.reimbursedDate || this.today());
            })
          if (this.advanced) {
          Column({ space: 10 }) {
            Row() {
              Text('累计已到账金额').fontSize(15).fontColor(Theme.textPrimary)
              Blank()
              Text('全额到账').fontSize(14).fontColor(Theme.accent)
                .padding(8).onClick(() => { this.received = this.bill.amount.toFixed(2); this.closed = true; })
            }.width('100%')
            TextInput({ text: this.received, placeholder: '未到账填 0' })
              .type(InputType.NUMBER_DECIMAL).fontSize(24).height(56)
              .backgroundColor(Theme.card).fontColor(Theme.textPrimary)
              .onChange((value: string) => { this.received = value; })
            Text('填写累计总额，不是本次新增金额。只扣除实际到账的报销。')
              .fontSize(12).fontColor(Theme.textSecondary).width('100%')
          }.width('100%')
          }
          if (Number(this.received) > 0 || !this.advanced) {
            Row() {
              Text('最近到账日期').fontSize(14).fontColor(Theme.textPrimary)
              Blank()
              Text(this.receivedDate + ' ›').fontSize(14).fontColor(Theme.accent)
                .padding({ top: 12, bottom: 12 })
                .onClick(() => {
                  DatePickerDialog.show({
                    start: new Date(this.bill.date), end: new Date(), selected: new Date(this.receivedDate),
                    onDateAccept: (date: Date) => {
                      this.receivedDate = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
                    }
                  });
                })
            }.width('100%')
          }
          if (this.advanced) {
          Row({ space: 10 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.closed })
              .onChange((value: boolean) => { this.closed = value; })
            Column({ space: 4 }) {
              Text('报销已结束').fontSize(14).fontColor(Theme.textPrimary)
              Text('只报一部分、不再报销，也可以勾选').fontSize(12).fontColor(Theme.textSecondary)
            }.alignItems(HorizontalAlign.Start)
          }.width('100%')
          Text('个人花销 ¥' + Math.max(0, this.bill.amount - (Number(this.received) || 0)).toFixed(2))
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary).width('100%')
          }
          Text('报销冲减 ' + this.bill.date.substring(0, 7) + ' 的个人花销，不算到账月份的收入。信用卡还款仍不计支出。')
            .fontSize(13).fontColor(Theme.textSecondary).width('100%')
          Text(this.saving ? '保存中…' : (this.advanced ? '保存报销' : ((this.bill.reimbursed ?? 0) >= this.bill.amount ? '已全额报销' : '确认全额到账')))
            .width('100%').height(52).textAlign(TextAlign.Center)
            .fontSize(16).fontColor(Theme.onAccent).backgroundColor(Theme.accent).borderRadius(14)
            .onClick(() => {
              if (this.advanced) { this.save(); }
              else if ((this.bill.reimbursed ?? 0) < this.bill.amount) { this.saveFull(); }
            })
        } else {
          Text('正在加载…').fontColor(Theme.textSecondary)
        }
      }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor(Theme.bg)
  }
}
