import { router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

// 兼容旧页面入口，实际内容由首页容器统一管理。
@Entry
@Component
struct StatsPage {
  aboutToAppear(): void {
    router.replaceUrl({ url: 'pages/Index', params: { tab: '月报' } });
  }
  build() {
    Column() { Text('正在打开月报…').fontColor(Theme.textSecondary) }
      .width('100%').height('100%').backgroundColor(Theme.bg).justifyContent(FlexAlign.Center)
  }
}
