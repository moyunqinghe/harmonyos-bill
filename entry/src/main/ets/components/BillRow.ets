import { Bill, BillStore } from '../common/BillStore';
import { MonthlyReport } from '../common/MonthlyReport';
import { Theme } from '../common/Theme';

@Component
export struct BillRow {
  @Prop bill: Bill = { id: 0, type: 'expense', amount: 0, note: '', date: '', image: '' };
  onOpen: (bill: Bill) => void = () => {};

  build() {
    Row({ space: 12 }) {
      Column() {
        Text(this.bill.type === 'expense' ? (this.bill.category || '支出').substring(0, 1) : BillStore.typeLabel(this.bill.type).substring(0, 1))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#465C57')
      }.width(40).height(44).justifyContent(FlexAlign.Center).borderRadius(13)
      .linearGradient({ angle: 110, colors: [[MonthlyReport.groupColors(this.bill.category || '')[0], 0], [MonthlyReport.groupColors(this.bill.category || '')[1], 1]] })
      Column({ space: 5 }) {
        Text(BillStore.displayTitle(this.bill)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(BillStore.detailLabel(this.bill)).fontSize(11).fontColor(Theme.textSecondary).maxLines(2)
        if (this.bill.image) { Text('附凭证').fontSize(10).fontColor(Theme.textSecondary) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(BillStore.amountPrefix(this.bill.type) + '¥' + this.bill.amount.toFixed(2))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary).maxLines(1).minFontSize(12).maxFontSize(16)
        if (this.bill.reimbursable) {
          Text('自付 ¥' + BillStore.personalExpense(this.bill).toFixed(2)).fontSize(11).fontColor(Theme.accent)
        }
      }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: '38%' })
    }.width('100%').padding({ top: 15, bottom: 15, left: 14, right: 14 })
    .backgroundColor(Theme.card).borderRadius(16)
    .onClick(() => { this.onOpen(this.bill); })
  }
}
