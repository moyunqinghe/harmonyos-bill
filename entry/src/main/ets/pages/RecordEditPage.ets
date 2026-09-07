import { router, promptAction, curves, KeyboardAvoidMode } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { Bill, BillStore } from '../common/BillStore';
import { Theme } from '../common/Theme';

@Entry
@Component
struct RecordEditPage {
  @State recordType: string = 'expense';
  @State date: string = '';
  @State amount: string = '';
  @State note: string = '';
  @State category: string = '';
  @State paymentMethod: string = '';
  @State choiceSheet: boolean = false;
  @State choiceKind: string = 'category';
  @State extraOpen: boolean = false;
  private autoReimbursement: boolean = false;
  @State pop: number = 1;
  @State noteFocused: boolean = false;
  @State entered: boolean = false;
  @State imageUri: string = '';
  @State reimbursable: boolean = false;
  @State saving: boolean = false;
  private reimbursed: number = 0;
  private reimbursedDate: string = '';
  private reimbursementClosed: boolean = false;
  private editId: number = -1;
  private persistedImage: string = ''; // 已入库的图片路径，用于保存时判断是否需要清理旧文件
  private keyRows: string[][] = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '←']
  ];
  private hasEntered: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const params = router.getParams() as Record<string, Object>;
    if (params && params.type) {
      this.recordType = params.type as string;
    }
    if (params && typeof params.id === 'number') {
      // 编辑模式：预填已有记录
      this.editId = params.id as number;
      this.amount = (params.amount as number).toString();
      this.note = params.note as string;
      this.category = (params.category as string) ?? '';
      this.paymentMethod = (params.paymentMethod as string) ?? '';
      this.date = params.date as string;
      this.imageUri = params.image as string;
      this.persistedImage = this.imageUri;
      this.reimbursable = (params.reimbursable as boolean) ?? false;
      this.reimbursed = (params.reimbursed as number) ?? 0;
      this.reimbursedDate = (params.reimbursedDate as string) ?? '';
      this.reimbursementClosed = (params.reimbursementClosed as boolean) ?? false;
    } else {
      this.date = RecordEditPage.fmtDate(new Date());
    }
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

  static deleteFileQuietly(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      // 文件不存在或已删除，忽略
    }
  }

  /** 从相册选一张图片，复制进应用沙盒后记录路径 */
  async pickImage(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const result = await photoPicker.select(opts);
      if (!result.photoUris || result.photoUris.length === 0) {
        return; // 用户取消
      }
      const context = getContext(this);
      const dir = context.filesDir + '/bill_images';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const dest = `${dir}/img_${Date.now()}.jpg`;
      // 相册 URI 不能直接按路径复制，需用文件描述符方式拷贝进沙盒
      const srcFile = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      // 替换掉本次会话里刚选过但未保存的旧图，避免垃圾文件
      if (this.imageUri.length > 0 && this.imageUri !== this.persistedImage) {
        RecordEditPage.deleteFileQuietly(this.imageUri);
      }
      this.imageUri = dest;
    } catch (e) {
      promptAction.showToast({ message: '图片选择失败，请重试' });
    }
  }

  async save(): Promise<void> {
    if (this.saving) { return; }
    if (this.reimbursed > 0 && (this.recordType !== 'expense' || !this.reimbursable || Number(this.amount) < this.reimbursed || this.date > this.reimbursedDate)) {
      promptAction.showToast({ message: '已有报销到账，请先在报销管理中更正' });
      return;
    }
    const value = Number(this.amount);
    if (!value || value <= 0) {
      promptAction.showToast({ message: '请输入金额' });
      return;
    }
    const bill: Bill = {
      id: this.editId >= 0 ? this.editId : 0,
      type: this.recordType,
      amount: Math.round(value * 100) / 100,
      note: this.note,
      date: this.date,
      image: this.imageUri,
      category: this.recordType === 'expense' ? this.category : '',
      paymentMethod: this.recordType === 'expense' ? this.paymentMethod : '',
      reimbursable: this.recordType === 'expense' && this.reimbursable,
      reimbursed: this.reimbursed,
      reimbursedDate: this.reimbursedDate,
      reimbursementClosed: this.reimbursementClosed
    };
    this.saving = true;
    try {
    if (this.editId >= 0) {
      await BillStore.update(getContext(this), bill);
      promptAction.showToast({ message: '已修改' });
    } else {
      await BillStore.add(getContext(this), bill);
      promptAction.showToast({ message: '已保存' });
    }
    // 图片被更换或移除时，清理已入库的旧文件
    if (this.persistedImage.length > 0 && this.persistedImage !== this.imageUri) {
      RecordEditPage.deleteFileQuietly(this.persistedImage);
    }
    router.back();
    } catch (e) {
      promptAction.showToast({ message: '保存失败，记录未提交，请重试' });
    } finally {
      this.saving = false;
    }
  }

  onPageShow(): void {
    if (this.editId >= 0) {
      BillStore.queryAll(getContext(this)).then((bills: Bill[]) => {
        const bill = bills.find((b: Bill) => b.id === this.editId);
        if (bill) {
          this.reimbursable = bill.reimbursable ?? false;
          this.reimbursed = bill.reimbursed ?? 0;
          this.reimbursedDate = bill.reimbursedDate ?? '';
          this.reimbursementClosed = bill.reimbursementClosed ?? false;
        }
      });
    }
  }

  selectCategory(value: string): void {
    this.category = this.category === value ? '' : value;
    if (this.category === '话费' && !this.reimbursable) {
      this.reimbursable = true;
      this.autoReimbursement = true;
    } else if (this.category !== '话费' && this.autoReimbursement && this.reimbursed === 0) {
      this.reimbursable = false;
      this.autoReimbursement = false;
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
        Text(this.editId >= 0 ? '修改记录' : '记一笔')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        Blank()
        Text(' ')
          .width(40)
      }
      .width('100%')

      Scroll() {
        Column() {
      // 常用类型直接点选，不再经过菜单
      Row() {
        this.SwitchTab('支出', 'expense')
        this.SwitchTab('收入', 'income')
        this.SwitchTab('还款', 'repayment')
        this.SwitchTab('转账', 'transfer')
      }
      .width('100%')
      .padding(4)
      .backgroundColor(Theme.card)
      .borderRadius(14)
      .margin({ top: 12 })

      if (BillStore.isNeutral(this.recordType)) {
        Text(this.recordType === 'repayment' ? '平台欠款统一记这里，不重复计入花销' : '自己账户间转账，不计收入和花销')
          .fontSize(12).fontColor(Theme.textSecondary).width('100%').margin({ top: 8 })
      }

      Row({ space: 10 }) {
        this.DateChip('今天', RecordEditPage.fmtDate(new Date()))
        this.DateChip('昨天', RecordEditPage.fmtDate(new Date(Date.now() - 86400000)))
        Text(this.date)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(Theme.card)
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
      .margin({ top: 12 })

      // 大号金额读数：按键时轻微回弹
      Row({ space: 6 }) {
        Text('¥')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(BillStore.isNeutral(this.recordType) ? Theme.accent : (this.recordType === 'income' ? Theme.income : Theme.expense))
        Text(this.amount.length > 0 ? this.amount : '0')
          .fontSize(46)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .letterSpacing(-1)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 12 })
      .scale({ x: this.pop, y: this.pop })
      .animation({ duration: 130, curve: Curve.EaseOut })
      .opacity(this.entered ? 1 : 0)
      .translate({ y: this.entered ? 0 : 16 })
      .animation({ duration: 350, curve: curves.cubicBezierCurve(0.22, 1, 0.36, 1) })

      if (this.recordType === 'expense') {
        Column({ space: 10 }) {
          this.ChoiceEntry('category')
          this.ChoiceEntry('payment')
        }.width('100%').margin({ top: 14, bottom: 8 })
      }

      if (this.recordType === 'expense') {
        Row({ space: 8 }) {
          if (this.editId < 0) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.reimbursable })
              .onChange((checked: boolean) => {
                if (checked !== this.reimbursable) { this.autoReimbursement = false; }
                this.reimbursable = checked;
              })
            Text('这笔需要报销')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
          } else {
            Text(this.reimbursable ? '管理报销 ›' : '登记报销 ›')
              .fontSize(14)
              .fontColor(Theme.accent)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/ReimbursementPage', params: { id: this.editId } });
              })
            Text('按已保存的消费登记')
              .fontSize(12)
              .fontColor(Theme.textSecondary)
          }
        }
        .width('100%')
      }


      Text(this.extraOpen ? '收起补充信息 ⌃' : (this.note || this.imageUri ? '补充信息 · 已填写 ›' : '补充信息 · 备注 / 凭证 ›'))
        .fontSize(13).fontColor(Theme.textSecondary).width('100%').padding({ top: 12, bottom: 12 })
        .onClick(() => { this.extraOpen = !this.extraOpen; })
      if (this.extraOpen) {
      Row({ space: 10 }) {
        TextInput({ placeholder: '补充说明（可不填）', text: this.note })
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
            .backgroundColor(Theme.accent)
            .borderRadius(10)
            .onClick(() => {
              this.hideKeyboard();
            })
        }
      }
      .width('100%')
      .margin({ top: 16 })

      // 凭证图片：选中后复制到沙盒，点缩略图可更换
      if (this.imageUri.length > 0) {
        Row({ space: 12 }) {
          Image('file://' + this.imageUri)
            .width(72)
            .height(72)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              this.pickImage();
            })
          Text('更换')
            .fontSize(13)
            .fontColor(Theme.accent)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.pickImage();
            })
          Text('移除')
            .fontSize(13)
            .fontColor(Theme.expense)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.imageUri = '';
            })
        }
        .width('100%')
        .margin({ top: 12 })
      } else {
        Row({ space: 6 }) {
          Text('＋')
            .fontSize(15)
            .fontColor(Theme.textSecondary)
          Text('添加图片（小票/凭证）')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
        }
        .width('100%')
        .margin({ top: 12 })
        .padding({ top: 10, bottom: 10 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.card)
        .borderRadius(10)
        .onClick(() => {
          this.pickImage();
        })
      }

      }
        }.width('100%').padding({ bottom: 8 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)

      if (!this.noteFocused) {
      Column({ space: 8 }) {
        ForEach(this.keyRows, (row: string[]) => {
          Row({ space: 10 }) {
            ForEach(row, (k: string) => {
              Text(k)
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor(k === '←' ? (BillStore.isNeutral(this.recordType) ? Theme.accent : (this.recordType === 'income' ? Theme.income : Theme.expense)) : Theme.textPrimary)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(46)
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

      }
      Text(this.saving ? '保存中…' : '保存')
        .id('billSaveButton').focusable(true)
        .width('100%')
        .height(46)
        .textAlign(TextAlign.Center)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.onAccent)
        .backgroundColor(Theme.accent)
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
    .bindSheet($$this.choiceSheet, this.ChoicePanel(), { height: SheetSize.FIT_CONTENT, showClose: true, dragBar: true, backgroundColor: Theme.bg })
  }

  @Builder
  ChoiceEntry(kind: string) {
    Row() {
      Text(kind === 'category' ? '花在哪' : '怎么付').fontSize(14).fontColor(Theme.textSecondary).layoutWeight(1)
      Text((kind === 'category' ? this.category : this.paymentMethod) || '暂不选择').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.textPrimary)
      Text('›').fontSize(20).fontColor(Theme.accent).margin({ left: 10 })
    }.width('100%').padding({ left: 16, right: 16 }).height(48).backgroundColor(Theme.card).borderRadius(14)
      .id('choose-' + kind).onClick(() => { this.hideKeyboard(); this.choiceKind = kind; this.choiceSheet = true; })
  }

  @Builder
  ChoicePanel() {
    Column({ space: 16 }) {
      Text(this.choiceKind === 'category' ? '花在哪' : '怎么付').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Theme.textPrimary).width('100%')
      Text('点选一项，自动返回记账').fontSize(12).fontColor(Theme.textSecondary).width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.choiceKind === 'category' ? BillStore.categories : BillStore.paymentMethods, (value: string) => {
          Text(value).id((this.choiceKind === 'category' ? 'category-' : 'payment-') + value)
            .fontSize(14).textAlign(TextAlign.Center).width('32%').height(48).margin({ bottom: 10 }).borderRadius(12)
            .fontColor((this.choiceKind === 'category' ? this.category : this.paymentMethod) === value ? Theme.onAccent : Theme.textPrimary)
            .backgroundColor((this.choiceKind === 'category' ? this.category : this.paymentMethod) === value ? Theme.accent : Theme.card)
            .onClick(() => {
              if (this.choiceKind === 'category') {
                if (this.category !== value) { this.selectCategory(value); }
              } else { this.paymentMethod = value; }
              this.choiceSheet = false;
            })
        }, (value: string) => value)
      }.width('100%')
      Button('暂不选择').width('100%').height(44).fontColor(Theme.textSecondary).backgroundColor(Theme.card)
        .onClick(() => {
          if (this.choiceKind === 'category') { if (this.category) { this.selectCategory(this.category); } }
          else { this.paymentMethod = ''; }
          this.choiceSheet = false;
        })
    }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 28 })
  }

  @Builder
  DateChip(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.date === value ? Theme.accent : Theme.textSecondary)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.date === value ? Theme.incomeCardStart : Theme.card)
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
      .fontColor(this.recordType === tabType ? Theme.textPrimary : Theme.textSecondary)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(44)
      .backgroundColor(this.recordType === tabType
        ? (tabType === 'expense' ? Theme.expenseCardStart : Theme.incomeCardStart)
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
