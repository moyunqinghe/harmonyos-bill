import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { picker, fileIo } from '@kit.CoreFileKit';
import { Bill, BillStore } from '../common/BillStore';
import { MonthlyReport } from '../common/MonthlyReport';
import { Theme } from '../common/Theme';

@Entry
@Component
struct ReportPage {
  @State month: string = '';
  @State ready: boolean = false;
  @State saving: boolean = false;
  @State error: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;
  private loaded: boolean = false;
  private initialized: boolean = false;
  private bills: Bill[] = [];

  aboutToAppear(): void {
    const d = new Date();
    const params = router.getParams() as Record<string, Object>;
    const requested = params?.month as string;
    this.month = requested && /^\d{4}-(0[1-9]|1[0-2])$/.test(requested) ? requested : `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
    BillStore.queryAll(getContext(this)).then((bills: Bill[]) => {
      this.bills = bills; this.loaded = true; this.renderReport();
    }).catch(() => { this.error = '账单读取失败，请返回后重试'; });
  }

  renderReport(): void {
    if (!this.attached || !this.loaded || !this.initialized) { return; }
    this.ready = false;
    try {
      this.controller.loadData(MonthlyReport.html(MonthlyReport.create(this.bills, this.month)), 'text/html', 'UTF-8', 'https://bill.invalid/');
    } catch (e) { this.error = '月报生成失败，请返回后重试'; }
  }

  shiftMonth(delta: number): void {
    if (this.saving || !this.ready) { return; }
    const parts = this.month.split('-');
    const d = new Date(Number(parts[0]), Number(parts[1]) - 1 + delta, 1);
    this.month = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
    this.renderReport();
  }

  async exportPdf(): Promise<void> {
    if (!this.ready || this.saving) { return; }
    this.saving = true;
    try {
      const result = await this.controller.createPdf({ width: 8.27, height: 11.69,
        marginTop: 0.4, marginBottom: 0.4, marginLeft: 0.4, marginRight: 0.4 });
      const bytes = result.pdfArrayBuffer();
      if (bytes.length < 5 || bytes[0] !== 37 || bytes[1] !== 80 || bytes[2] !== 68 || bytes[3] !== 70) { throw new Error('PDF 生成失败'); }
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`Bill-${this.month}-消费月报.pdf`];
      const uris = await new picker.DocumentViewPicker(getContext(this)).save(opts);
      if (!uris || uris.length === 0) { return; }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)); }
      finally { fileIo.closeSync(file); }
      promptAction.showToast({ message: '可视化月报已保存为 PDF' });
    } catch (e) { promptAction.showToast({ message: 'PDF 导出失败，请重试' }); }
    finally { this.saving = false; }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹').fontSize(26).width(40).onClick(() => { if (!this.saving) { router.back(); } })
        Text('可视化月报').fontSize(21).fontWeight(FontWeight.Bold).layoutWeight(1)
      }.width('100%')
      Row() {
        Button('上个月').onClick(() => this.shiftMonth(-1)).enabled(this.ready && !this.saving)
        Text(this.month).fontSize(18).textAlign(TextAlign.Center).layoutWeight(1)
        Button('下个月').onClick(() => this.shiftMonth(1)).enabled(this.ready && !this.saving)
      }.width('100%')
      if (this.error) { Text(this.error).fontColor(Theme.expense) }
      Web({ src: 'about:blank', controller: this.controller })
        .javaScriptAccess(false).domStorageAccess(false).fileAccess(false)
        .onControllerAttached(() => { this.attached = true; })
        .onPageEnd(() => {
          if (!this.initialized) { this.initialized = true; this.renderReport(); return; }
          if (this.loaded && this.controller.getTitle() === `Bill ${this.month} 月报`) { this.ready = true; }
        })
        .width('100%').layoutWeight(1)
      Button(this.saving ? '正在导出…' : (this.ready ? '保存 PDF 月报' : '正在生成月报…'))
        .width('100%').height(48).backgroundColor(Theme.accent)
        .enabled(this.ready && !this.saving && !this.error)
        .onClick(() => { this.exportPdf(); })
    }.width('100%').height('100%').padding(20).backgroundColor(Theme.bg)
  }
}
