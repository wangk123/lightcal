# 轻卡 LightCal

个人自用的 iOS 减脂打卡 App：拍照 / 语音 / 文字快速记录饮食，自动统计热量与蛋白质、脂肪、碳水，对照目标计算缺口并给出补充食物建议；运动消耗自动读取 Apple Health；根据历史摄入与消耗趋势动态估算减脂速率与目标达成时间。

- **平台**：iOS 17+ 原生（SwiftUI），仅个人自用
- **隐私**：数据仅存本机，照片不出设备，媒体即用即弃
- **状态**：v1 实现完成 + 今日记录增强（饮水时间线、左滑删除、肉类细分食物库、图标完善），全量单测 + UI 测试全绿，待真机手工验证

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
