# 安装到 iPhone（LiveContainer 免费方案）

目标：免开发者账号、免 7 天重签，把「轻卡」装到自己 iPhone 长期使用。

## 前提

- iPhone 系统 iOS 16+（本 App 要求 iOS 17+）
- 一台 Mac（本项目电脑，Xcode 26+）
- 一次性完成以下配置，之后升级 App 只需重复「构建与安装」

## 一次性准备：安装 LiveContainer 容器

1. 从 [LiveContainer 官方仓库](https://github.com/LiveContainer/LiveContainer) 的 Releases 下载 `LiveContainer` 的 IPA
2. 用免费 Apple ID 把它安装到 iPhone（三选一，只需一次）：
   - 用 AltStore / SideStore 安装（SideStore 装好后可脱离电脑在手机上自动续签）
   - 或数据线连接 Mac，用 Xcode 免费账号签名安装
3. iPhone 上打开 LiveContainer，完成初始化

> LiveContainer 是容器应用：装一次容器，之后向容器里安装的 App 不受 7 天签名限制，也不需要各自签名。

## 构建与安装「轻卡」

1. 在本仓库运行：
   ```bash
   ./scripts/export-ipa.sh
   ```
2. 得到 `build/LightCal.ipa`
3. 把 IPA 传到 iPhone（AirDrop 或「文件」App 的 iCloud）
4. iPhone 上长按 IPA →「打开方式」→ 选择 LiveContainer → 安装
5. 打开 LiveContainer，点击「轻卡」图标启动

## 首次启动配置

1. 完成建档向导（身体数据 + 目标体重）
2. 「我的」→ 设置 → 填 DeepSeek API Key（不填也能用：食物库与自定义食物完全可用，仅自然语言解析/营养估算降级为本地规则）
3. 允许 HealthKit 授权（读取运动消耗）
4. 「我的」→ 隐私说明确认：数据仅存本机，照片不出设备

## 更新版本

重复「构建与安装」第 1–5 步即可（容器无需重装）。

## 数据备份

「我的」→ 导出备份 (JSON)。换机时按原样重建数据，或将来实现导入功能。

## 真机手工验证清单（发布前必做）

- [ ] 建档向导正常保存，仪表盘显示目标
- [ ] HealthKit 授权弹窗；佩戴 Apple Watch 时「消耗」数据非 0
- [ ] 拍照识别：拍鸡胸肉+米饭 → 候选食物 → 确认卡片（识别 API 为 VNClassifyImageRequest，见设计文档裁决记录）
- [ ] 语音输入：说「一碗米饭两个鸡蛋」→ 转写 → 解析 2 条
- [ ] 无网络时文字录入仍可用（本地正则兜底）
- [ ] 深色模式正常；LiveContainer 内启动正常
