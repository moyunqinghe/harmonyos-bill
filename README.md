# Bill · 鸿蒙记账 App

一款基于 HarmonyOS（ArkTS / ArkUI）开发的轻量级记账应用，数据本地存储，简洁美观。

## 功能特性

- **快速记账**：一键记录收入 / 支出，支持金额与备注
- **本月概览**：首页彩虹渐变卡片实时展示本月结余、收入与支出总额（带数字滚动动画）
- **账单记录**：按日期浏览全部账单，支持删除
- **统计分析**：图表化查看收支构成，看懂钱花在哪
- **本地存储**：基于关系型数据库（relationalStore / RDB），数据完全保存在设备本地，无需联网

## 技术栈

- **系统**：HarmonyOS（runtimeOS: HarmonyOS）
- **语言 / UI**：ArkTS + ArkUI（声明式 UI，Stage 模型）
- **数据层**：`@kit.ArkData` relationalStore（SQLite）
- **路由**：`@kit.ArkUI` router
- **构建工具**：Hvigor（hvigorw）

## 环境要求

- DevEco Studio 5.x+
- HarmonyOS SDK：compileSdkVersion 26.0.0，compatibleSdkVersion 6.1.0(23)

## 快速开始

1. 用 DevEco Studio 打开本仓库根目录
2. 在 DevEco Studio 中配置自己的签名（File → Project Structure → Signing Configs）
3. 连接设备或启动模拟器，点击 Run 运行

> 本仓库已移除所有签名配置与本地路径，需使用你自己的开发者证书签名后构建。

## 项目结构

```
├── AppScope/                  # 应用级配置（bundleName、版本、图标）
├── entry/                     # 主模块
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/  # EntryAbility 入口
│       │   ├── common/        # 数据层（BillStore）、主题（Theme）、动画（Anim）
│       │   └── pages/         # 页面：首页 / 记账编辑 / 账单记录 / 统计分析
│       └── resources/         # 字符串、颜色、图标资源
├── build-profile.json5        # 工程构建配置（不含签名信息）
└── oh-package.json5           # 依赖声明
```

## 数据说明

账单数据存储于应用沙箱内的 `bill.db`，表结构：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER | 主键，自增 |
| type | TEXT | `income`（收入）/ `expense`（支出） |
| amount | REAL | 金额 |
| note | TEXT | 备注 |
| date | TEXT | 日期，格式 `yyyy-MM-dd` |

## License

仅供学习交流使用。
