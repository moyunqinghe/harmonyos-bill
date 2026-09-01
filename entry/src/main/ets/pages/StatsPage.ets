import { router, display } from '@kit.ArkUI';
import { Bill, BillStore } from '../common/BillStore';
import { tween } from '../common/Anim';
import { Theme } from '../common/Theme';

interface StatParams {
  label: string;
  value: string;
  color: ResourceColor;
}

@Entry
@Component
struct StatsPage {
  @State month: string = '';
  @State incomeTotal: number = 0;
  @State expenseTotal: number = 0;
  private bills: Bill[] = [];
  private dailyExpense: number[] = [];
  private progress: number = 0;
  private zoomScale: number = 1;
  private offsetX: number = 0;
  private baseZoom: number = 1;
  private baseOffsetX: number = 0;
  private touchX: number = -1;
  private chartW: number = 0;
  private fontScale: number = 1;
  private chartTimer: number = -1;
  private pieReady: boolean = false;
  private barReady: boolean = false;
  private pieSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private pieCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieSettings);
  private barSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private barCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.barSettings);

  aboutToAppear(): void {
    const now = new Date();
    this.month = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}`;
    try {
      this.fontScale = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      this.fontScale = 1;
    }
    this.load();
  }

  /** Canvas font 的 px 是物理像素，按屏幕密度放大后才等于视觉 vp 大小 */
  fp(size: number, bold: boolean = false): string {
    return `${bold ? 'bold ' : ''}${Math.round(size * this.fontScale)}px sans-serif`;
  }

  onPageShow(): void {
    this.load();
  }

  async load(): Promise<void> {
    this.bills = await BillStore.queryAll(getContext(this));
    this.compute();
  }

  shiftMonth(delta: number): void {
    const parts = this.month.split('-');
    const d = new Date(Number(parts[0]), Number(parts[1]) - 1 + delta, 1);
    this.month = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
    this.compute();
  }

  compute(): void {
    const list = this.bills.filter((b: Bill) => b.date.startsWith(this.month));
    let income = 0;
    let expense = 0;
    const parts = this.month.split('-');
    const days = new Date(Number(parts[0]), Number(parts[1]), 0).getDate();
    this.dailyExpense = new Array<number>(days).fill(0);
    list.forEach((b: Bill) => {
      if (b.type === 'income') {
        income += b.amount;
      } else {
        expense += b.amount;
        const day = Number(b.date.substring(8, 10));
        if (day >= 1 && day <= days) {
          this.dailyExpense[day - 1] += b.amount;
        }
      }
    });
    this.incomeTotal = income;
    this.expenseTotal = expense;
    if (this.chartTimer >= 0) {
      clearInterval(this.chartTimer);
    }
    this.progress = 0;
    this.chartTimer = tween(0, 1, 650, (v: number) => {
      this.progress = v;
      this.drawDonut();
      this.drawBar();
    });
  }

  private css(res: Resource): string {
    const n = getContext(this).resourceManager.getColorSync(res);
    return '#' + (n & 0xFFFFFF).toString(16).padStart(6, '0');
  }

  private rgba(cssHex: string, alpha: number): string {
    const r = parseInt(cssHex.substring(1, 3), 16);
    const g = parseInt(cssHex.substring(3, 5), 16);
    const b = parseInt(cssHex.substring(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  drawDonut(): void {
    if (!this.pieReady) {
      return;
    }
    const ctx = this.pieCtx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2;
    const lw = 24;
    const r = Math.min(w, h) / 2 - lw / 2 - 4;
    ctx.lineWidth = lw;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    if (this.incomeTotal <= 0 && this.expenseTotal <= 0) {
      ctx.strokeStyle = this.css(Theme.track);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = this.css(Theme.textSecondary);
      ctx.font = this.fp(13);
      ctx.fillText('暂无数据', cx, cy);
      return;
    }

    // 圆环口径：整环=收入，弧=支出，圆心=支出占收入比
    const p = this.progress;
    if (this.incomeTotal > 0) {
      ctx.strokeStyle = this.css(Theme.income);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2 * p);
      ctx.stroke();
    }
    if (this.expenseTotal > 0) {
      const ratio = this.incomeTotal > 0 ? Math.min(this.expenseTotal / this.incomeTotal, 1) : 1;
      ctx.strokeStyle = this.css(Theme.expense);
      ctx.beginPath();
      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + ratio * Math.PI * 2 * p);
      ctx.stroke();
    }

    ctx.fillStyle = this.css(Theme.textPrimary);
    ctx.font = this.fp(20, true);
    if (this.incomeTotal > 0) {
      const pct = Math.round((this.expenseTotal / this.incomeTotal) * 100);
      ctx.fillText(pct + '%', cx, cy - 10);
      ctx.fillStyle = this.css(Theme.textSecondary);
      ctx.font = this.fp(12);
      ctx.fillText('支出占收入', cx, cy + 16);
    } else {
      ctx.fillText('-¥' + this.expenseTotal.toFixed(0), cx, cy - 10);
      ctx.fillStyle = this.css(Theme.textSecondary);
      ctx.font = this.fp(12);
      ctx.fillText('本月无收入记录', cx, cy + 16);
    }
  }

  clampOffset(): void {
    const days = this.dailyExpense.length;
    if (days < 2 || this.chartW <= 0) {
      this.offsetX = 0;
      return;
    }
    const padX = 6;
    const stepX = (this.chartW - padX * 2) / (days - 1);
    const contentW = padX * 2 + stepX * this.zoomScale * (days - 1);
    const min = Math.min(0, this.chartW - contentW);
    this.offsetX = Math.min(Math.max(this.offsetX, min), 0);
  }

  drawBar(): void {
    if (!this.barReady) {
      return;
    }
    const ctx = this.barCtx;
    const w = ctx.width;
    const h = ctx.height;
    this.chartW = w;
    ctx.clearRect(0, 0, w, h);
    const days = this.dailyExpense.length;
    if (days === 0) {
      return;
    }
    const lineColor = this.css(Theme.chartLine);
    const secondaryColor = this.css(Theme.textSecondary);
    const axisH = 18;
    const chartH = h - axisH;
    const padX = 6;
    const stepX = days > 1 ? (w - padX * 2) / (days - 1) : 0;
    const px = (i: number): number => days > 1 ? padX + i * stepX * this.zoomScale + this.offsetX : w / 2;
    const max = Math.max(...this.dailyExpense);
    const topPad = 22;
    const py = (v: number): number => chartH - 4 - (v / Math.max(max, 1)) * (chartH - 4 - topPad);

    ctx.strokeStyle = this.css(Theme.track);
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, chartH - 1);
    ctx.lineTo(w, chartH - 1);
    ctx.stroke();

    if (max <= 0) {
      ctx.fillStyle = secondaryColor;
      ctx.font = this.fp(16);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('本月暂无支出', w / 2, chartH / 2);
      return;
    }

    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, w * this.progress, h);
    ctx.clip();

    const tracePath = () => {
      // 中点抛物线插值：以相邻点中点为终点、数据点为控制点，曲线更圆润
      ctx.moveTo(px(0), py(this.dailyExpense[0]));
      for (let i = 1; i < days; i++) {
        const midX = (px(i - 1) + px(i)) / 2;
        const midY = (py(this.dailyExpense[i - 1]) + py(this.dailyExpense[i])) / 2;
        ctx.quadraticCurveTo(px(i - 1), py(this.dailyExpense[i - 1]), midX, midY);
      }
      ctx.lineTo(px(days - 1), py(this.dailyExpense[days - 1]));
    };

    const grad = ctx.createLinearGradient(0, 0, 0, chartH);
    grad.addColorStop(0, this.rgba(lineColor, 0.32));
    grad.addColorStop(1, this.rgba(lineColor, 0));
    ctx.beginPath();
    tracePath();
    ctx.lineTo(px(days - 1), chartH - 1);
    ctx.lineTo(px(0), chartH - 1);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    ctx.beginPath();
    tracePath();
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 2.5;
    ctx.stroke();

    // 滑动探针：竖线 + 高亮点 + 当天消费浮层
    if (this.touchX >= 0 && stepX > 0) {
      let idx = Math.round((this.touchX - padX - this.offsetX) / (stepX * this.zoomScale));
      idx = Math.min(Math.max(idx, 0), days - 1);
      const x = px(idx);
      const v = this.dailyExpense[idx];
      const y = py(v);

      ctx.strokeStyle = this.rgba(lineColor, 0.45);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, 4);
      ctx.lineTo(x, chartH - 1);
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      ctx.lineWidth = 2.5;
      ctx.strokeStyle = lineColor;
      ctx.stroke();

      const dayLabel = `${Number(this.month.split('-')[1])}月${idx + 1}日`;
      const detail = v > 0 ? `¥${v.toFixed(2)}` : '无支出';
      // 无浮层框：文字独立悬浮，背景色描边光晕保证可读性
      let tx = x + 14;
      ctx.textAlign = 'left';
      if (tx + 120 > w) {
        tx = x - 14;
        ctx.textAlign = 'right';
      }
      const ty = Math.max(y - 58, 4);
      ctx.textBaseline = 'top';
      ctx.lineWidth = 5 * this.fontScale;
      ctx.strokeStyle = this.css(Theme.bg);
      ctx.font = this.fp(16, true);
      ctx.strokeText(detail, tx, ty);
      ctx.fillStyle = this.css(Theme.textPrimary);
      ctx.fillText(detail, tx, ty);
      ctx.font = this.fp(13);
      ctx.strokeText(dayLabel, tx, ty + 32);
      ctx.fillStyle = secondaryColor;
      ctx.fillText(dayLabel, tx, ty + 32);
    }
    ctx.restore();

    // 底部日期刻度（放大字号）
    ctx.fillStyle = secondaryColor;
    ctx.font = this.fp(12);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    for (let d = 1; d <= days; d += 5) {
      const x = px(d - 1);
      if (x >= -10 && x <= w + 10) {
        ctx.fillText(d.toString(), x, chartH + 3);
      }
    }
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
        Text('统计分析')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
        Blank()
        Text(' ')
          .width(40)
      }
      .width('100%')
      .padding({ bottom: 14 })

      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Text('‹')
              .fontSize(20)
              .fontColor(Theme.textPrimary)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => this.shiftMonth(-1))
            Text(this.month)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text('›')
              .fontSize(20)
              .fontColor(Theme.textPrimary)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => this.shiftMonth(1))
          }
          .width('100%')
          .padding(4)
          .backgroundColor(Theme.card)
          .borderRadius(14)

          Row({ space: 10 }) {
            this.StatCard({ label: '收入', value: '+¥' + this.incomeTotal.toFixed(2), color: Theme.income })
            this.StatCard({ label: '支出', value: '-¥' + this.expenseTotal.toFixed(2), color: Theme.expense })
            this.StatCard({ label: '结余', value: '¥' + (this.incomeTotal - this.expenseTotal).toFixed(2), color: Theme.accent })
          }
          .width('100%')

          Column({ space: 14 }) {
            Text('收支对比')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .width('100%')
            Canvas(this.pieCtx)
              .width('100%')
              .height(190)
              .onReady(() => {
                this.pieReady = true;
                this.drawDonut();
              })
            Row({ space: 18 }) {
              Row({ space: 6 }) {
                Circle({ width: 8, height: 8 }).fill(Theme.income)
                Text(`收入 ¥${this.incomeTotal.toFixed(2)}`)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary)
              }
              Row({ space: 6 }) {
                Circle({ width: 8, height: 8 }).fill(Theme.expense)
                Text(`支出 ¥${this.expenseTotal.toFixed(2)}`)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary)
              }
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.card)
          .borderRadius(18)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 14 }) {
            Text('每日支出')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .width('100%')
            Canvas(this.barCtx)
              .width('100%')
              .height(170)
              .onReady(() => {
                this.barReady = true;
                this.drawBar();
              })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down || e.type === TouchType.Move) {
                  this.touchX = e.touches[0].x;
                } else {
                  this.touchX = -1;
                }
                this.drawBar();
              })
              .gesture(
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.baseZoom = this.zoomScale;
                  })
                  .onActionUpdate((e: GestureEvent) => {
                    const newScale = Math.min(Math.max(this.baseZoom * e.scale, 1), 5);
                    const anchor = this.chartW / 2;
                    this.offsetX = anchor - (anchor - this.offsetX) * (newScale / this.zoomScale);
                    this.zoomScale = newScale;
                    this.clampOffset();
                    this.drawBar();
                  })
              )
              .parallelGesture(
                PanGesture({ fingers: 1, distance: 6 })
                  .onActionStart(() => {
                    this.baseOffsetX = this.offsetX;
                  })
                  .onActionUpdate((e: GestureEvent) => {
                    if (this.zoomScale > 1) {
                      this.offsetX = this.baseOffsetX + e.offsetX;
                      this.clampOffset();
                      this.drawBar();
                    }
                  })
              )
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.card)
          .borderRadius(18)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor(Theme.bg)
  }

  @Builder
  StatCard(p: StatParams) {
    Column({ space: 6 }) {
      Text(p.label)
        .fontSize(12)
        .fontColor(Theme.textSecondary)
      Text(p.value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(p.color)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(Theme.card)
    .borderRadius(14)
  }
}
