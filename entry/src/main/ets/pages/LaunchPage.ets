import { router, curves } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

@Entry
@Component
struct LaunchPage {
  @State appeared: boolean = false;
  @State leaving: boolean = false;
  @State failed: boolean = false;
  private revealTimer: number = -1;
  private enterTimer: number = -1;
  private opening: boolean = false;

  aboutToAppear(): void {
    this.revealTimer = setTimeout(() => { this.appeared = true; }, 30);
    this.enterTimer = setTimeout(() => { this.enterLedger(); }, 1100);
  }

  aboutToDisappear(): void {
    clearTimeout(this.revealTimer);
    clearTimeout(this.enterTimer);
  }

  onBackPress(): boolean {
    this.enterLedger();
    return true;
  }

  enterLedger(): void {
    if (this.opening) { return; }
    this.opening = true;
    this.leaving = true;
    clearTimeout(this.enterTimer);
    router.replaceUrl({ url: 'pages/Index' }).catch(() => {
      this.opening = false;
      this.leaving = false;
      this.failed = true;
    });
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('Bill').fontSize(23).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
        Text('生活小账本').fontSize(12).fontColor(Theme.textSecondary)
        Blank()
        Row({ space: 4 }) {
          Circle({ width: 6, height: 6 }).fill('#B9D8F5')
          Circle({ width: 6, height: 6 }).fill('#B3DED0')
          Circle({ width: 6, height: 6 }).fill('#D5C4EE')
        }
      }.width('100%')
      Blank().layoutWeight(1)

      Column({ space: 14 }) {
        Row() {
          Text('每一笔生活').fontSize(12).letterSpacing(2).fontColor(Theme.textSecondary)
          Blank()
          Text('都值得记下').fontSize(12).fontColor(Theme.textSecondary)
        }.width('100%').margin({ bottom: 8 })

        Row({ space: 14 }) {
          Text('01').fontSize(13).fontColor('#9D7754')
          Text('日常消费').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#534C43').layoutWeight(1)
          Text('记下当下').fontSize(12).fontColor('#89796A')
        }.width('100%').height(64).padding({ left: 20, right: 20 }).borderRadius(18)
        .linearGradient({ angle: 100, colors: [['#FFF0D9', 0], ['#FBE4DC', 1]] })
        .rotate({ angle: this.appeared ? -3 : -7 })
        .opacity(this.appeared ? 1 : 0).translate({ x: this.appeared ? -4 : -24, y: this.appeared ? 0 : 16 })
        .animation({ duration: 460, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

        Row({ space: 14 }) {
          Text('02').fontSize(13).fontColor('#6886AC')
          Text('平台还款').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#405777').layoutWeight(1)
          Text('不重复计支出').fontSize(12).fontColor('#6E83A0')
        }.width('100%').height(64).padding({ left: 20, right: 20 }).borderRadius(18)
        .linearGradient({ angle: 100, colors: [['#E1EEFF', 0], ['#E9E5FA', 1]] })
        .rotate({ angle: this.appeared ? 2 : 6 })
        .opacity(this.appeared ? 1 : 0).translate({ x: this.appeared ? 4 : 24, y: this.appeared ? 0 : 16 })
        .animation({ duration: 460, delay: 90, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

        Row({ space: 14 }) {
          Text('03').fontSize(13).fontColor('#638D7E')
          Text('话费报销').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#3D6354').layoutWeight(1)
          Text('到账后扣除').fontSize(12).fontColor('#708D80')
        }.width('100%').height(64).padding({ left: 20, right: 20 }).borderRadius(18)
        .linearGradient({ angle: 100, colors: [['#DDF3E9', 0], ['#EAF1D9', 1]] })
        .rotate({ angle: this.appeared ? -1 : -5 })
        .opacity(this.appeared ? 1 : 0).translate({ x: this.appeared ? 0 : -16, y: this.appeared ? 0 : 16 })
        .animation({ duration: 460, delay: 180, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })
      }.width('100%').constraintSize({ maxWidth: 360 })

      Column({ space: 8 }) {
        Text('记下生活，').fontSize(29).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
        Text('算清自己的花销。').fontSize(29).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary)
        Text('简单记一笔，心里有个数。').fontSize(13).fontColor(Theme.textSecondary).margin({ top: 10 })
      }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 38 })
      .opacity(this.appeared ? 1 : 0).translate({ y: this.appeared ? 0 : 10 })
      .animation({ duration: 380, delay: 220, curve: Curve.EaseOut })

      Blank().layoutWeight(1)
      Row() {
        Text(this.failed ? '暂时未能打开账本，请点右侧重试' : '只算自己真正承担的花销')
          .fontSize(11).fontColor(Theme.textSecondary).layoutWeight(1)
        Text(this.failed ? '重试 ›' : '进入账本 ›').id('enterLedger')
          .fontSize(13).fontColor(Theme.accent).padding({ top: 16, bottom: 16, left: 12 })
          .onClick(() => { this.enterLedger(); })
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 30, right: 30, top: 30, bottom: 18 })
    .backgroundColor(Theme.bg)
    .opacity(this.leaving ? 0 : 1).animation({ duration: 150, curve: Curve.EaseOut })
  }
}
