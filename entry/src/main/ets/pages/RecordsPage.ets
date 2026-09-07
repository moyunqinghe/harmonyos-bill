import { router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

// 兼容旧页面入口，实际内容由首页容器统一管理。
@Entry
@Component
struct RecordsPage {
  aboutToAppear(): void {
    router.replaceUrl({ url: 'pages/Index', params: { tab: '账单' } });
  }
  build() {
    Column() { Text('正在打开账单…').fontColor(Theme.textSecondary) }
      .width('100%').height('100%').backgroundColor(Theme.bg).justifyContent(FlexAlign.Center)
  }
}
