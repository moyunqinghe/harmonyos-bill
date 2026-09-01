import { router, promptAction, curves } from '@kit.ArkUI';
import { BillStore } from '../common/BillStore';
import { Theme } from '../common/Theme';

@Entry
@Component
struct RecordEditPage {
  @State recordType: string = 'expense';
  @State date: string = '';
  @State amount: string = '';
  @State note: string = '';
  @State pop: number = 1;
  @State noteFocused: boolean = false;
  @State entered: boolean = false;
  private keyRows: string[][] = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '←']
  ];
  private hasEntered: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params.type) {
      this.recordType = params.type;
    }
    this.date = RecordEditPage.fmtDate(new Date());
    if (!this.hasEntered) {
      this.hasEntered = true;
      setTimeout(() => {
        this.entered = true;
      }, 30);
    }
  }

  static fmtDate(d: Date): string {
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  get isFixedDate(): boolean {
    const today = RecordEditPage.fmtDate(new Date());
    const y = new Date();
    y.setDate(y.getDate() - 1);
    return this.date === today || this.date === RecordEditPage.fmtDate(y);
  }

  onKey(k: string): void {
    if (k === '←') {
      this.amount = this.amount.slice(0, -1);
    } else if (k === '.') {
      if (!this.amount.includes('.')) {
        this.amount = this.amount.length > 0 ? this.amount + '.' : '0.';
      }
    } else if (this.amount.includes('.') && this.amount.split('.')[1].length >= 2) {
      return;
    } else if (this.amount === '0') {
      this.amount = k;
    } else if (this.amount.replace('.', '').length >= 9) {
      return;
    } else {
      this.amount += k;
    }
    this.pop = 1.07;
    setTimeout(() => {
      this.pop = 1;
    }, 90);
  }

  hideKeyboard(): void {
    // 把焦点移到保存按钮上，输入框失焦，系统键盘随之收起
    focusControl.requestFocus('billSaveButton');
  }

  async save(): Promise<void> {
    const value = Number(this.amount);
    if (!value || value <= 0) {
      promptAction.showToast({ message: '请输入金额' });
      return;
    }
    await BillStore.add(getContext(this), {
      id: 0,
      type: this.recordType,
      amount: Math.round(value * 100) / 100,
      note: this.note,
      date: this.date
    });
    promptAction.showToast({ message: '已保存' });
    router.back();
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
        Text('记一笔')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        Blank()
        Text(' ')
          .width(40)
      }
      .width('100%')

      // 收支切换：选中态背景色渐变过渡
      Row() {
        this.SwitchTab('支出', 'expense')
        this.SwitchTab('收入', 'income')
      }
      .width('100%')
      .padding(4)
      .backgroundColor(Theme.card)
      .borderRadius(14)
      .margin({ top: 18 })

      Row({ space: 10 }) {
        this.DateChip('今天', RecordEditPage.fmtDate(new Date()))
        this.DateChip('昨天', RecordEditPage.fmtDate(new Date(Date.now() - 86400000)))
        Text(this.isFixedDate ? '选择日期' : this.date)
          .fontSize(13)
          .fontColor(this.isFixedDate ? Theme.textSecondary : Theme.onAccent)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.isFixedDate ? Theme.card : (this.recordType === 'income' ? Theme.income : Theme.expense))
          .borderRadius(10)
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            DatePickerDialog.show({
              start: new Date('2000-01-01'),
              end: new Date('2100-12-31'),
              selected: new Date(this.date),
              onDateAccept: (d: Date) => {
                this.date = RecordEditPage.fmtDate(d);
              }
            })
          })
      }
      .width('100%')
      .margin({ top: 18 })

      // 大号金额读数：按键时轻微回弹
      Row({ space: 6 }) {
        Text('¥')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.recordType === 'income' ? Theme.income : Theme.expense)
        Text(this.amount.length > 0 ? this.amount : '0')
          .fontSize(46)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .letterSpacing(-1)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 22 })
      .scale({ x: this.pop, y: this.pop })
      .animation({ duration: 130, curve: Curve.EaseOut })
      .opacity(this.entered ? 1 : 0)
      .translate({ y: this.entered ? 0 : 16 })
      .animation({ duration: 350, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

      Row({ space: 10 }) {
        TextInput({ placeholder: '备注（可选）', text: this.note })
          .fontSize(15)
          .height(48)
          .backgroundColor(Theme.card)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textSecondary)
          .borderRadius(10)
          .enterKeyType(EnterKeyType.Done)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.note = v;
          })
          .onFocus(() => {
            this.noteFocused = true;
          })
          .onBlur(() => {
            this.noteFocused = false;
          })
          .onSubmit(() => {
            this.hideKeyboard();
          })
        if (this.noteFocused) {
          Text('完成')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.onAccent)
            .textAlign(TextAlign.Center)
            .width(56)
            .height(48)
            .backgroundColor(this.recordType === 'income' ? Theme.income : Theme.expense)
            .borderRadius(10)
            .onClick(() => {
              this.hideKeyboard();
            })
        }
      }
      .width('100%')
      .margin({ top: 16 })

      Blank()

      Column({ space: 10 }) {
        ForEach(this.keyRows, (row: string[]) => {
          Row({ space: 10 }) {
            ForEach(row, (k: string) => {
              Text(k)
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor(k === '←' ? (this.recordType === 'income' ? Theme.income : Theme.expense) : Theme.textPrimary)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(54)
                .backgroundColor(Theme.card)
                .borderRadius(10)
                .stateStyles({
                  pressed: {
                    .scale({ x: 0.88, y: 0.88 })
                    .backgroundColor(Theme.track)
                  }
                })
                .onClick(() => this.onKey(k))
            }, (k: string) => k)
          }
          .width('100%')
        }, (row: string[]) => row.join(''))
      }
      .width('100%')
      .opacity(this.entered ? 1 : 0)
      .translate({ y: this.entered ? 0 : 24 })
      .animation({ duration: 400, delay: 80, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

      Text('保存')
        .id('billSaveButton')
        .width('100%')
        .height(54)
        .textAlign(TextAlign.Center)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.onAccent)
        .backgroundColor(this.recordType === 'income' ? Theme.income : Theme.expense)
        .borderRadius(14)
        .margin({ top: 16 })
        .stateStyles({
          pressed: {
            .scale({ x: 0.97, y: 0.97 })
            .opacity(0.9)
          }
        })
        .onClick(() => {
          this.save();
        })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(Theme.bg)
  }

  @Builder
  DateChip(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.date === value ? Theme.onAccent : Theme.textSecondary)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.date === value ? (this.recordType === 'income' ? Theme.income : Theme.expense) : Theme.card)
      .borderRadius(10)
      .animation({ duration: 200, curve: Curve.EaseOut })
      .onClick(() => {
        this.date = value;
      })
  }

  @Builder
  SwitchTab(label: string, tabType: string) {
    Text(label)
      .fontSize(16)
      .fontWeight(this.recordType === tabType ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.recordType === tabType ? Theme.onAccent : Theme.textSecondary)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(44)
      .backgroundColor(this.recordType === tabType
        ? (tabType === 'income' ? Theme.income : Theme.expense)
        : Color.Transparent)
      .borderRadius(11)
      .animation({ duration: 220, curve: Curve.EaseOut })
      .stateStyles({
        pressed: {
          .scale({ x: 0.95, y: 0.95 })
        }
      })
      .onClick(() => {
        this.recordType = tabType;
      })
  }
}
