import { router, promptAction } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { Bill, BillStore } from '../common/BillStore';
import { MonthlyReport, ReportData, ReportGroup } from '../common/MonthlyReport';
import { LedgerPresentation, LedgerGroup } from '../common/LedgerPresentation';
import { Theme } from '../common/Theme';
import { BillRow } from '../components/BillRow';

@Entry
@Component
struct Index {
  @State tab: string = '首页';
  @State filter: string = '全部';
  @State bills: Bill[] = [];
  @State groups: LedgerGroup[] = [];
  @State home: ReportData = MonthlyReport.create([], '2000-01');
  @State report: ReportData = MonthlyReport.create([], '2000-01');
  @State reportMonth: string = '';
  @State pendingCount: number = 0;
  @State pendingCents: number = 0;
  @State loading: boolean = true;
  @State error: string = '';
  @State exporting: boolean = false;
  private loadVersion: number = 0;
  private filters: string[] = ['全部', '支出', '收入', '还款／转账', '待报销'];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params && params.tab) { this.tab = params.tab as string; }
    this.reportMonth = this.currentMonth();
    this.load();
  }

  onPageShow(): void { this.load(); }

  currentMonth(): string {
    const d = new Date();
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
  }

  async load(): Promise<void> {
    const version = ++this.loadVersion;
    try {
      const bills = await BillStore.queryAll(getContext(this));
      if (version !== this.loadVersion) { return; }
      this.bills = bills;
      this.home = MonthlyReport.create(bills, this.currentMonth());
      this.report = MonthlyReport.create(bills, this.reportMonth || this.currentMonth());
      this.groups = LedgerPresentation.groups(bills, this.filter);
      const pending = bills.filter((bill: Bill) => LedgerPresentation.isPending(bill));
      this.pendingCount = pending.length;
      this.pendingCents = pending.reduce((sum: number, bill: Bill) => sum + Math.round(BillStore.personalExpense(bill) * 100), 0);
      this.error = '';
    } catch (e) { this.error = '账本暂时没能打开，请重试'; }
    finally { if (version === this.loadVersion) { this.loading = false; } }
  }

  money(cents: number): string { return MonthlyReport.money(cents); }

  openBill(bill: Bill): void {
    if (this.filter === '待报销' && this.tab === '账单') {
      router.pushUrl({ url: 'pages/ReimbursementPage', params: { id: bill.id } });
    } else {
      router.pushUrl({ url: 'pages/RecordEditPage', params: bill });
    }
  }

  chooseFilter(value: string): void {
    this.filter = value;
    this.groups = LedgerPresentation.groups(this.bills, value);
  }

  shiftMonth(delta: number): void {
    const parts = this.reportMonth.split('-');
    const d = new Date(Number(parts[0]), Number(parts[1]) - 1 + delta, 1);
    this.reportMonth = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
    this.report = MonthlyReport.create(this.bills, this.reportMonth);
  }

  async exportCsv(): Promise<void> {
    if (this.exporting) { return; }
    this.exporting = true;
    try {
      const bills = await BillStore.queryAll(getContext(this));
      if (!bills.length) { promptAction.showToast({ message: '暂无数据可导出' }); return; }
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`Bill-${this.currentMonth()}-全部明细.csv`];
      const uris = await new picker.DocumentViewPicker(getContext(this)).save(opts);
      if (!uris || !uris.length) { return; }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, BillStore.csvContent(bills)); } finally { fileIo.closeSync(file); }
      promptAction.showToast({ message: `已导出 ${bills.length} 条记录` });
    } catch (e) { promptAction.showToast({ message: '导出失败，请重试' }); }
    finally { this.exporting = false; }
  }

  confirmDelete(bill: Bill): void {
    AlertDialog.show({ title: '删除这条记录？', message: `${bill.date} ${BillStore.displayTitle(bill)} ${this.money(Math.round(bill.amount * 100))}，删除后无法恢复。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: Theme.expense, action: async () => {
        try { await BillStore.remove(getContext(this), bill.id); this.load(); }
        catch (e) { promptAction.showToast({ message: '删除失败，请重试' }); }
      } }
    });
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.tab === '首页' ? 'Bill' : this.tab).fontSize(27).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
          Text(this.tab === '首页' ? '生活小账本' : (this.tab === '账单' ? '每一笔，都有去处' : '看清这个月的生活'))
            .fontSize(12).fontColor(Theme.textSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.tab === '账单') {
          Button(this.exporting ? '导出中' : '导出 CSV').fontSize(12).fontColor(Theme.accent).backgroundColor(Theme.card)
            .enabled(!this.exporting).onClick(() => { this.exportCsv(); })
        } else {
          Text(this.tab === '首页' ? this.home.month.replace('-', ' / ') : '月度回顾').fontSize(12).fontColor(Theme.textSecondary)
        }
      }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 18 })

      if (this.loading || this.error) {
        Column({ space: 16 }) {
          Text(this.loading ? '正在打开账本…' : this.error).fontColor(Theme.textSecondary)
          if (this.error) { Button('重新加载').onClick(() => { this.load(); }) }
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.tab === '首页') {
        Scroll() {
          Column() { ForEach([this.home], (data: ReportData) => { this.HomeContent() },
            (data: ReportData) => JSON.stringify(data) + JSON.stringify(this.bills)) }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      } else if (this.tab === '账单') {
        this.LedgerContent()
      } else {
        Scroll() {
          Column() { ForEach([this.report], (data: ReportData) => { this.MonthContent() },
            (data: ReportData) => JSON.stringify(data)) }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }

      Column({ space: 8 }) {
        Button('＋ 记一笔').id('newBill').fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(Theme.onAccent).backgroundColor(Theme.accent).width('100%').height(48).borderRadius(16)
          .onClick(() => { router.pushUrl({ url: 'pages/RecordEditPage', params: { type: 'expense' } }); })
        Row() {
          ForEach(['首页', '账单', '月报'], (value: string) => {
            Column({ space: 4 }) {
              Text(value).fontSize(14).fontWeight(this.tab === value ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.tab === value ? Theme.accent : Theme.textSecondary)
              Rect().width(this.tab === value ? 18 : 0).height(3).radius(2).fill(Theme.accent)
            }.height(44).layoutWeight(1).justifyContent(FlexAlign.Center).id('tab-' + value)
              .onClick(() => { this.tab = value; })
          }, (value: string) => value)
        }.width('100%')
      }.width('100%').padding({ left: 22, right: 22, top: 10, bottom: 8 }).backgroundColor(Theme.bg)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  HomeContent() {
    Column({ space: 18 }) {
      Column({ space: 14 }) {
        Row() {
          Text('本月个人花销').fontSize(14).fontColor(Theme.textSecondary).layoutWeight(1)
          Text('自己的生活账').fontSize(11).fontColor(Theme.textSecondary)
        }.width('100%')
        Text(this.money(this.home.personal)).fontSize(42).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
          .maxLines(1).minFontSize(25).maxFontSize(42).width('100%')
        Divider().color(Theme.cardBorder)
        Row() {
          this.SmallAmount('消费原额', this.home.gross)
          Text('−').fontColor(Theme.textSecondary).margin({ left: 18, right: 18 })
          this.SmallAmount('已到账报销', this.home.received)
          Blank()
        }.width('100%')
      }.width('100%').padding(22).alignItems(HorizontalAlign.Start).borderRadius(24)
        .linearGradient({ angle: 115, colors: [[Theme.incomeCardStart, 0], [Theme.card, 1]] })

      Row() {
        Column({ space: 6 }) {
          Text('待报销').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary)
          Text('全部月份 · ' + this.pendingCount + ' 笔').fontSize(12).fontColor(Theme.textSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.money(this.pendingCents)).fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary)
        Text('›').fontSize(22).fontColor(Theme.accent).margin({ left: 12 })
      }.width('100%').padding(18).backgroundColor(Theme.card).borderRadius(20)
        .onClick(() => { this.chooseFilter('待报销'); this.tab = '账单'; })

      Row({ space: 12 }) {
        this.Metric('本月收入', this.home.income)
        this.Metric('本月还款 · 不计花销', this.home.repayment)
      }.width('100%')
      Row() {
        Text('最近五笔').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).layoutWeight(1)
        Text('全部账单 ›').fontSize(13).fontColor(Theme.accent).padding(8)
          .onClick(() => { this.chooseFilter('全部'); this.tab = '账单'; })
      }.width('100%')
      if (!this.bills.length) { this.EmptyState('还没有记录', '点下方「记一笔」，记下今天的生活。') }
      ForEach(this.bills.slice(0, 5), (bill: Bill) => {
        Column({ space: 5 }) {
          Text(bill.date).fontSize(11).fontColor(Theme.textSecondary).width('100%').padding({ left: 4 })
          BillRow({ bill: bill, onOpen: (value: Bill) => { this.openBill(value); } })
        }
      }, (bill: Bill) => JSON.stringify(bill))
    }.padding({ left: 22, right: 22, bottom: 10 }).width('100%')
  }

  @Builder
  LedgerContent() {
    Column({ space: 10 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.filters, (value: string) => {
            Button(value).fontSize(12).height(38).fontColor(this.filter === value ? Theme.onAccent : Theme.textSecondary)
              .backgroundColor(this.filter === value ? Theme.accent : Theme.card)
              .onClick(() => { this.chooseFilter(value); })
          }, (value: string) => value)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      Text('全部时间 · 明细保留原金额，日汇总为个人收支').fontSize(11).fontColor(Theme.textSecondary).width('100%')
      if (!this.groups.length) {
        this.EmptyState(this.filter === '待报销' ? '没有待报销记录' : '这里还没有记录', this.filter === '待报销' ? '已结束的报销可以在全部账单中查看。' : '换个筛选，或记下新的一笔。')
        Blank()
      } else {
        List({ space: 8 }) {
          ForEach(this.groups, (group: LedgerGroup) => {
            ListItemGroup({ header: this.GroupHeader(group) }) {
              ForEach(group.items, (bill: Bill) => {
                ListItem() {
                  BillRow({ bill: bill, onOpen: (value: Bill) => { this.openBill(value); } })
                }.margin({ bottom: 8 }).swipeAction({ end: { builder: () => { this.DeleteButton(bill) } } })
              }, (bill: Bill) => JSON.stringify(bill))
            }
          }, (group: LedgerGroup) => group.date + JSON.stringify(group.items))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
    }.padding({ left: 22, right: 22 }).width('100%').layoutWeight(1)
  }

  @Builder
  MonthContent() {
    Column({ space: 18 }) {
      Row() {
        Button('‹').id('previousMonth').fontSize(22).fontColor(Theme.textPrimary).backgroundColor(Theme.card).onClick(() => this.shiftMonth(-1))
        Text(this.reportMonth).fontSize(20).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).layoutWeight(1).textAlign(TextAlign.Center)
        Button('›').id('nextMonth').fontSize(22).fontColor(Theme.textPrimary).backgroundColor(Theme.card).onClick(() => this.shiftMonth(1))
      }.width('100%')
      Column({ space: 10 }) {
        Text('个人实际花销').fontSize(14).fontColor(Theme.textSecondary)
        Text(this.money(this.report.personal)).fontSize(34).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary).maxLines(1).minFontSize(22).maxFontSize(34)
        Text('消费 ' + this.money(this.report.gross) + ' − 已报销 ' + this.money(this.report.received)).fontSize(12).fontColor(Theme.textSecondary)
      }.width('100%').padding(22).alignItems(HorizontalAlign.Start).borderRadius(22)
        .linearGradient({ angle: 110, colors: [[Theme.incomeCardStart, 0], [Theme.card, 1]] })
      Button('导出本月 PDF ›').id('exportMonthPdf').width('100%').height(44).backgroundColor(Theme.card).fontColor(Theme.accent)
        .onClick(() => { router.pushUrl({ url: 'pages/ReportPage', params: { month: this.reportMonth } }); })
      this.Distribution('钱花在哪', '个人花销 · 扣除已到账报销', this.report.categories, this.report.personal, false)
      this.Distribution('用什么支付', '原消费金额，包含垫付；不是待还金额', this.report.payments, this.report.gross, true)
      Column({ space: 12 }) {
        Text('每日个人花销').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).width('100%')
        Text('最高 ' + this.money(Math.max(0, ...this.report.daily))).fontSize(11).fontColor(Theme.textSecondary).width('100%')
        Row({ space: 3 }) {
          ForEach(this.report.daily, (cents: number, index: number) => {
            Column() {
              Blank()
              Column().width('100%').height(cents > 0 ? Math.max(2, cents / Math.max(1, ...this.report.daily) * 84) : 1)
                .backgroundColor(cents > 0 ? Theme.accent : Theme.track).borderRadius(3)
            }.height(90).layoutWeight(1)
              .onClick(() => { promptAction.showToast({ message: `${index + 1}日 · ${this.money(cents)}` }); })
          }, (cents: number, index: number) => `${index}-${cents}-${this.reportMonth}`)
        }.width('100%')
        Row() {
          Text('1日').fontSize(11).fontColor(Theme.textSecondary)
          Blank()
          Text('点击查看当天金额').fontSize(10).fontColor(Theme.textSecondary)
          Blank()
          Text(this.report.daily.length + '日').fontSize(11).fontColor(Theme.textSecondary)
        }.width('100%')
      }.width('100%').padding(18).borderRadius(20).backgroundColor(Theme.card)
      Row({ space: 10 }) { this.Metric('收入', this.report.income)
        this.Metric('收支差额', this.report.income - this.report.personal) }.width('100%')
      Row({ space: 10 }) { this.Metric('还款 · 不计花销', this.report.repayment)
        this.Metric('转账 · 不计收支', this.report.transfer) }.width('100%')
      Text('本月消费尚待报销 ' + this.money(this.report.pending) + '\n报销到账后，会更新原消费月份的个人花销。')
        .fontSize(12).fontColor(Theme.textSecondary).width('100%')
    }.width('100%').padding({ left: 22, right: 22, bottom: 12 })
  }

  @Builder
  Distribution(title: string, subtitle: string, groups: ReportGroup[], total: number, payment: boolean) {
    Column({ space: 12 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).width('100%')
      Text(subtitle).fontSize(11).fontColor(Theme.textSecondary).width('100%')
      if (!groups.length) { Text('本月没有消费记录').fontSize(13).fontColor(Theme.textSecondary).padding(12) }
      ForEach(groups, (group: ReportGroup) => {
        Column({ space: 7 }) {
          Row() {
            Text(group.label).fontSize(13).fontColor(Theme.textPrimary).layoutWeight(1)
            Text(this.money(group.cents) + '  ' + (total > 0 ? group.cents / total * 100 : 0).toFixed(1) + '%')
              .fontSize(12).fontColor(Theme.textSecondary)
          }.width('100%')
          Stack({ alignContent: Alignment.Start }) {
            Column().width('100%').height(8).backgroundColor(Theme.track).borderRadius(4)
            Column().width((total > 0 ? group.cents / total * 100 : 0) + '%').height(8).borderRadius(4)
              .linearGradient({ angle: 90, colors: [[MonthlyReport.groupColors(group.label, payment)[0], 0], [MonthlyReport.groupColors(group.label, payment)[1], 1]] })
          }.width('100%')
        }
      }, (group: ReportGroup) => group.label + group.cents)
    }.padding(18).width('100%').backgroundColor(Theme.card).borderRadius(20)
  }

  @Builder
  SmallAmount(label: string, cents: number) {
    Column({ space: 5 }) {
      Text(label).fontSize(11).fontColor(Theme.textSecondary)
      Text(this.money(cents)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary)
    }.alignItems(HorizontalAlign.Start)
  }

  @Builder
  Metric(label: string, cents: number) {
    Column({ space: 7 }) {
      Text(label).fontSize(11).fontColor(Theme.textSecondary)
      Text(this.money(cents)).fontSize(19).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).maxLines(1).minFontSize(12).maxFontSize(19)
    }.layoutWeight(1).padding(16).backgroundColor(Theme.card).borderRadius(18).alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState(title: string, subtitle: string) {
    Column({ space: 10 }) {
      Text(title).fontSize(17).fontColor(Theme.textPrimary)
      Text(subtitle).fontSize(12).fontColor(Theme.textSecondary).textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 32, bottom: 32 })
  }

  @Builder
  GroupHeader(group: LedgerGroup) {
    Row() {
      Text(group.date).fontSize(12).fontColor(Theme.textSecondary).layoutWeight(1)
      Text(group.summary).fontSize(11).fontColor(Theme.textSecondary)
    }.width('100%').padding({ top: 14, bottom: 10 })
  }

  @Builder
  DeleteButton(bill: Bill) {
    Text('删除').fontSize(14).fontColor(Color.White).backgroundColor(Theme.expense).width(72).height('100%')
      .textAlign(TextAlign.Center).borderRadius(14).onClick(() => { this.confirmDelete(bill); })
  }
}
