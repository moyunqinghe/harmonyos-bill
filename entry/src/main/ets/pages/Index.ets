import { router, curves } from '@kit.ArkUI';
import { Bill, BillStore } from '../common/BillStore';
import { Theme } from '../common/Theme';
import { tween } from '../common/Anim';

interface PillParams {
  label: string;
  value: string;
  dotColor: string;
}

@Entry
@Component
struct Index {
  @State incomeTotal: number = 0;
  @State expenseTotal: number = 0;
  @State displayBalance: number = 0;
  @State monthLabel: string = '';
  @State recentBills: Bill[] = [];
  @State entered: boolean = false;
  private balance: number = 0;
  private balanceTimer: number = -1;
  private hasEntered: boolean = false;

  aboutToAppear(): void {
    this.load();
    if (!this.hasEntered) {
      this.hasEntered = true;
      setTimeout(() => {
        this.entered = true;
      }, 30);
    }
  }

  onPageShow(): void {
    this.load();
  }

  async load(): Promise<void> {
    const now = new Date();
    const prefix = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}`;
    this.monthLabel = `${now.getFullYear()}.${(now.getMonth() + 1).toString().padStart(2, '0')}`;
    const bills = await BillStore.queryAll(getContext(this));
    let income = 0;
    let expense = 0;
    bills.forEach((b: Bill) => {
      if (!b.date.startsWith(prefix)) {
        return;
      }
      if (b.type === 'income') {
        income += b.amount;
      } else {
        expense += b.amount;
      }
    });
    this.incomeTotal = income;
    this.expenseTotal = expense;
    this.recentBills = bills.slice(0, 5);
    this.balance = income - expense;
    if (this.balanceTimer >= 0) {
      clearInterval(this.balanceTimer);
    }
    this.balanceTimer = tween(this.displayBalance, this.balance, 600, (v: number) => {
      this.displayBalance = v;
    });
  }

  static fmt(n: number): string {
    return n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  build() {
    Column() {
      Row() {
        Text('Bill')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .letterSpacing(-0.5)
        Blank()
        Text('记账 · 每一天')
          .fontSize(12)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')

      // 彩虹主视觉：底层彩虹渐变 + 高斯模糊，过渡自然
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [
              ['#FF6B8A', 0.0],
              ['#FFA94D', 0.22],
              ['#FFD43B', 0.42],
              ['#51CF8A', 0.62],
              ['#4DABF7', 0.82],
              ['#9775FA', 1.0]
            ]
          })
          .blur(30)
        Column({ space: 16 }) {
          Row() {
            Text('本月结余')
              .fontSize(13)
              .fontColor('#E6FFFFFF')
            Blank()
            Text(this.monthLabel)
              .fontSize(12)
              .fontColor('#B3FFFFFF')
          }
          .width('100%')
          Text('¥ ' + Index.fmt(this.displayBalance))
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .letterSpacing(-1)
            .width('100%')
            .maxLines(1)
            .textShadow({ radius: 6, color: '#40000000' })
          Row({ space: 10 }) {
            this.HeroPill({ label: '收入', value: '+¥' + Index.fmt(this.incomeTotal), dotColor: '#A7F3D0' })
            this.HeroPill({ label: '支出', value: '-¥' + Index.fmt(this.expenseTotal), dotColor: '#FDA4AF' })
          }
          .width('100%')
        }
        .width('100%')
        .padding(24)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(210)
      .borderRadius(24)
      .clip(true)
      .shadow({ radius: 24, color: '#33FF6B8A', offsetY: 10 })
      .margin({ top: 20 })
      .opacity(this.entered ? 1 : 0)
      .translate({ y: this.entered ? 0 : 24 })
      .animation({ duration: 420, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

      Row({ space: 14 }) {
        this.ActionCard('记收入', '+', 'income', Theme.incomeCardStart, Theme.incomeCardEnd, Theme.income, 140)
        this.ActionCard('记支出', '-', 'expense', Theme.expenseCardStart, Theme.expenseCardEnd, Theme.expense, 210)
      }
      .width('100%')
      .margin({ top: 14 })

      // 最近账单：填充中部空间
      Row() {
        Text('最近账单')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        Blank()
        Text('查看全部 ›')
          .fontSize(13)
          .fontColor(Theme.accent)
          .onClick(() => {
            router.pushUrl({ url: 'pages/RecordsPage' });
          })
      }
      .width('100%')
      .margin({ top: 20, bottom: 10 })
      .opacity(this.entered ? 1 : 0)
      .animation({ duration: 420, delay: 260, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

      if (this.recentBills.length === 0) {
        Column({ space: 8 }) {
          Text('还没有记录')
            .fontSize(14)
            .fontColor(Theme.textSecondary)
          Text('点上方卡片，记下第一笔')
            .fontSize(12)
            .fontColor(Theme.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.recentBills, (item: Bill) => {
            ListItem() {
              Row() {
                Circle({ width: 8, height: 8 })
                  .fill(item.type === 'income' ? Theme.income : Theme.expense)
                Text(item.note.length > 0 ? item.note : (item.type === 'income' ? '收入' : '支出'))
                  .fontSize(14)
                  .fontColor(Theme.textPrimary)
                  .maxLines(1)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                Text(item.date.substring(5))
                  .fontSize(12)
                  .fontColor(Theme.textSecondary)
                  .margin({ right: 12 })
                Text((item.type === 'income' ? '+' : '-') + '¥' + item.amount.toFixed(2))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.type === 'income' ? Theme.income : Theme.expense)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor(Theme.card)
              .borderRadius(12)
            }
          }, (item: Bill) => item.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      Row({ space: 14 }) {
        this.SubCard('账单记录', '按日期浏览每一笔', 'pages/RecordsPage', 330)
        this.SubCard('统计分析', '图表看懂钱花在哪', 'pages/StatsPage', 400)
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(Theme.bg)
  }

  @Builder
  HeroPill(p: PillParams) {
    Row({ space: 6 }) {
      Circle({ width: 6, height: 6 })
        .fill(p.dotColor)
      Text(p.label)
        .fontSize(12)
        .fontColor('#E6FFFFFF')
      Text(p.value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .backgroundColor('#2EFFFFFF')
    .borderRadius(20)
  }

  @Builder
  ActionCard(title: string, symbol: string, recordType: string, c1: ResourceColor, c2: ResourceColor,
    accent: ResourceColor, delay: number) {
    Column({ space: 8 }) {
      Row() {
        Circle({ width: 8, height: 8 })
          .fill(accent)
        Blank()
        Text(symbol)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent)
      }
      .width('100%')
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
        .width('100%')
      Text('记一笔')
        .fontSize(12)
        .fontColor(Theme.textSecondary)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(116)
    .padding(18)
    .backgroundColor(c1)
    .border({ width: 1, color: c2 })
    .borderRadius(16)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 24 })
    .animation({ duration: 420, delay: delay, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })
    .stateStyles({
      pressed: {
        .scale({ x: 0.94, y: 0.94 })
      }
    })
    .onClick(() => {
      router.pushUrl({ url: 'pages/RecordEditPage', params: { type: recordType } });
    })
  }

  @Builder
  SubCard(title: string, desc: string, url: string, delay: number) {
    Column({ space: 4 }) {
      Row() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        Blank()
        Text('›')
          .fontSize(18)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')
      Text(desc)
        .fontSize(11)
        .fontColor(Theme.textSecondary)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(16)
    .backgroundColor(Theme.card)
    .borderRadius(18)
    .border({ width: 1, color: Theme.cardBorder })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 24 })
    .animation({ duration: 420, delay: delay, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })
    .stateStyles({
      pressed: {
        .scale({ x: 0.95, y: 0.95 })
      }
    })
    .onClick(() => {
      router.pushUrl({ url: url });
    })
  }
}
