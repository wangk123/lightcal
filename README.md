# 轻卡 LightCal

个人自用的 iOS 减脂打卡 App：拍照 / 语音 / 文字快速记录饮食，自动统计热量与蛋白质、脂肪、碳水，对照目标计算缺口并给出补充食物建议；运动消耗自动读取 Apple Health；根据历史摄入与消耗趋势动态估算减脂速率与目标达成时间。

- **平台**：iOS 17+ 原生（SwiftUI），仅个人自用
- **隐私**：数据仅存本机，照片不出设备，媒体即用即弃
- **状态**：v1 实现完成 + 今日记录增强（饮水时间线、左滑删除、肉类细分食物库、图标完善）+ 饮品 ml 解析，全量单测 + UI 测试全绿，已安装真机验证

### 录入解析能力

文字 / 语音输入的常见句式都能解析成结构化条目：

- 克重：`100g鸡胸肉`、`鸡胸肉100g`、`100克牛肉`（kg/公斤 ×1000）
- 数量：`两个鸡蛋`、`一碗米饭`、`二十个饺子`（支持中文数字，如 五百/一百五十）
- 体积：`美式咖啡500ml`、`500ml 牛奶`、`五百毫升牛奶`、`2升牛奶`（升 ×1000）
- 份量单位自适应：饮品（咖啡/牛奶/水/茶/果汁等 27 种，含美式咖啡、豆浆、奶茶等新增条目）以 **ml** 展示与编辑，固体食物以 **g** 展示；解析自带 ml → ml，`一杯牛奶` → 250ml，`一碗米饭` → 200g，用户明确写克 → g
- 纯「数字+单位」（如 `500ml`、`100g`、`五百毫升`）不会被当作食物条目
- DeepSeek 不可用时本地正则兜底；两者都失败时原始输入保留进确认卡片，输入永不丢失

## 文档

- 设计文档：[docs/superpowers/specs/2026-08-20-diet-tracker-design.md](docs/superpowers/specs/2026-08-20-diet-tracker-design.md)
- 实现计划：[docs/superpowers/plans/2026-08-20-lightcal-implementation.md](docs/superpowers/plans/2026-08-20-lightcal-implementation.md)
- 安装指南：[docs/INSTALL.md](docs/INSTALL.md)
- 今日记录增强设计：[docs/superpowers/specs/2026-08-21-today-log-improvements-design.md](docs/superpowers/specs/2026-08-21-today-log-improvements-design.md)

## 构建与测试

```bash
xcodegen generate            # 生成工程
./scripts/ensure-simulator.sh  # 首次准备模拟器
xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 真机安装

前提：Xcode 已登录 Apple ID（免费个人团队可装，描述文件 7 天过期需重装续期），手机已开启开发者模式。

```bash
# 1. 查看连接的设备 ID
xcrun devicectl list devices

# 2. 构建 Release（TEAM ID 用证书 OU 字段值，非证书名括号里的编号）
xcodebuild -project LightCal.xcodeproj -scheme LightCal -configuration Release \
  -destination 'platform=iOS,id=<设备ID>' -derivedDataPath build/dd \
  DEVELOPMENT_TEAM=<TeamID> -allowProvisioningUpdates build

# 3. 安装并启动
xcrun devicectl device install app --device <设备ID> \
  build/dd/Build/Products/Release-iphoneos/LightCal.app
xcrun devicectl device process launch --device <设备ID> com.wangk123.lightcal
```
