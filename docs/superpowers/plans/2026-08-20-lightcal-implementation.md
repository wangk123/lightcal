# 「轻卡」LightCal 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一款仅个人自用的 iOS 减脂打卡 App「轻卡」：拍照/语音/文字快速记录饮食，对照 HealthKit 运动消耗与营养目标计算缺口、给出补充食物建议，并动态估算减脂速率与达标时间。

**Architecture:** 单体 Xcode 工程（xcodegen 生成），SwiftUI + SwiftData + HealthKit + Vision + Speech + Swift Charts。计算层（营养公式、速率预测、建议清单）为纯 Swift 函数模块直接单测；服务层（DeepSeek、HealthKit、Vision、语音）全部走 protocol 抽象，UI 只依赖协议，测试用 mock 注入。所有录入经统一管线 → 可编辑确认卡片 → 用户确认后落库。

**Tech Stack:** Swift 6 + SwiftUI、SwiftData、HealthKit、Vision（VNRecognizeFoodInSceneRequest）、Speech（SFSpeechRecognizer）、Swift Charts、DeepSeek API（URLSession）、XcodeGen、XCTest/XCUITest。部署目标 iOS 17.0。零第三方 UI 库。

**Spec:** `docs/superpowers/specs/2026-08-20-diet-tracker-design.md`（本计划逐条落实该规格，执行者两份都读）

## Global Constraints

- iOS 17.0+（SWIFT_VERSION 6.0、SWIFT_STRICT_CONCURRENCY=complete、SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated，UI 显式 @MainActor）
- 项目名 LightCal，bundle id `com.wangk123.lightcal`，App 显示名「轻卡」；工程由 `project.yml`（xcodegen）生成，**不手工编辑 .xcodeproj**
- 零第三方 UI 库；图标一律 SF Symbols，禁止 emoji 当图标；UI 文案中文
- 设计令牌统一走 `DesignTokens`：主色 `#0891B2`、强调 `#059669`、浅底 `#ECFEFF`、超支红 `#DC2626`、AI 估算琥珀 `#D97706`；代码中禁止裸写 hex 颜色
- 触控目标 ≥ 44pt、相邻间距 ≥ 8pt；AI 解析/识别期间必须显示 ProgressView；尊重「减弱动态效果」（accessibilityReduceMotion）
- **媒体硬约束**：照片/语音音频/AI 响应一律不落盘（内存即用即弃）；磁盘只存文字与数字（打卡、体重、目标、自定义食物）
- **确认卡片闸门**：任何 AI/识别结果不直接落库，必须用户点保存才写入
- 营养快照冗余存储于 FoodLogItem（历史记录不随数据源变化）；营养结构用 NutritionFacts 核心字段 + extras 扩展字典
- 减脂速率是派生值（体重趋势 0.6 + 能量趋势 0.4 加权），非用户输入；饮水量不参与热量/速率计算
- 营养数据三层兜底：内置库 → 自定义食物 → AI 估算（打 source 标记）；AI 估算条目不进建议候选池
- 体重趋势窗口 = 最近 14 天、≥3 个点才启用；1 kg 脂肪 ≈ 7700 kcal；BMR 用 Mifflin-St Jeor；热量目标下限 ≥ BMR；蛋白默认 1.8 g/kg
- 测试命令统一：`xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/<ClassName>`；每个任务以 git commit 收尾
- 提交信息格式：`feat:`/`fix:`/`docs:` + 中文简述

## File Structure

```
project.yml                          xcodegen 配置（工程唯一入口）
scripts/ensure-simulator.sh          下载 iOS 运行时并创建 iPhone 16 模拟器
scripts/export-ipa.sh                无签名导出 IPA（LiveContainer 用）
LightCal/
├─ App/
│  ├─ LightCalApp.swift              入口（--uitest 时内存库+种子数据）
│  └─ AppContainer.swift             依赖装配单例（Task 15）
├─ Models/
│  ├─ NutritionFacts.swift           营养快照（核心字段+extras，Codable）
│  ├─ ParsedFoodItem.swift           MealKind、ParsedFoodItem、FoodTextParsing 协议
│  ├─ SwiftDataModels.swift          UserProfile/Goal/CustomFood/FoodLogItem/WaterLogItem/WeightRecord
│  └─ DataStore.swift                SwiftData CRUD 与每日聚合
├─ FoodDatabase/
│  ├─ FoodRecord.swift               FoodRecord、FoodDatabaseFile
│  └─ FoodDatabase.swift             加载/精确匹配/搜索
├─ Logging/
│  ├─ LoggingPipeline.swift          LogDraft、LoggingPipelining、FoodPhotoRecognizing
│  ├─ TextParser/
│  │  ├─ LocalRegexParser.swift      离线正则兜底
│  │  ├─ DeepSeekClient.swift        DeepSeek 客户端（协议+重试+JSON 解码）
│  │  └─ URLSessionProtocol.swift    URLSession 抽象（测试注入）
│  ├─ PhotoRecognizer/
│  │  └─ VisionFoodRecognizer.swift  Vision 食物识别 + 中英文标签映射
│  └─ SpeechTranscriber/
│     └─ SpeechTranscriber.swift     流式转写（音频不落盘）、SpeechTranscribing 协议
├─ Nutrition/
│  └─ NutritionCompletion.swift      NutritionSource、CompletedFoodItem、PortionDefaults、三层兜底
├─ HealthKitService/
│  └─ HealthKitService.swift         HealthKitServing 协议 + 实现
├─ Goals/
│  ├─ NutritionCalculator.swift      Sex/ProfileInput/DailyTargets/WeightSample、BMR/TDEE/默认目标/饮水
│  ├─ LinearRegression.swift         最小二乘拟合
│  ├─ RateCalculator.swift           体重趋势速率、能量趋势速率
│  └─ PredictionCalculator.swift     综合速率、达标天数、三情景
├─ Recommendations/
│  └─ RecommendationEngine.swift     GapAnalysis、FoodSuggestion、建议清单
├─ UI/
│  ├─ DesignTokens.swift             颜色/尺寸令牌
│  ├─ Formatting.swift               数值格式化（纯函数，可测）
│  ├─ RootTabView.swift              3 Tab + 浮动录入按钮
│  ├─ Onboarding/                    建档与目标向导（Task 15）
│  ├─ Today/                         仪表盘 ViewModel + View（Task 16）
│  ├─ Logging/                       确认卡片、录入入口、相机/相册（Task 16/17）
│  ├─ Trends/                        趋势图表（Task 18）
│  └─ Profile/                       我的页、设置、导出（Task 19）
└─ Resources/
   └─ foods.json                     内置食物库（约 16 条种子数据）
LightCalTests/                        单元/集成测试（每任务对应一个测试文件）
LightCalUITests/                      UI 冒烟测试
docs/INSTALL.md                      LiveContainer 安装文档（Task 20）
```

---

### Task 1: 工程脚手架

**Files:**
- Create: `project.yml`
- Create: `scripts/ensure-simulator.sh`
- Create: `LightCal/App/LightCalApp.swift`
- Create: `LightCal/UI/DesignTokens.swift`
- Create: `LightCalTests/SmokeTests.swift`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `LightCal.xcodeproj`（生成物）、scheme `LightCal`、`DesignTokens.primary/accent/background/destructive/aiAmber`、`Color(hex:)`、模拟器 `iPhone 16`。后续所有任务的测试都依赖本任务的 scheme 与模拟器。

- [ ] **Step 1: 安装 xcodegen**

```bash
brew install xcodegen
```

- [ ] **Step 2: 写 project.yml**

```yaml
name: LightCal
options:
  bundleIdPrefix: com.wangk123
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    CODE_SIGN_STYLE: Automatic
targets:
  LightCal:
    type: application
    platform: iOS
    sources: [LightCal]
    info:
      path: LightCal/Info.plist
      properties:
        CFBundleDisplayName: 轻卡
        UILaunchScreen: {}
        NSHealthShareUsageDescription: 用于读取运动消耗与体重数据，计算每日能量收支
        NSHealthUpdateUsageDescription: 用于把体重与饮水记录写回健康
        NSCameraUsageDescription: 用于拍摄食物照片进行本地识别
        NSPhotoLibraryUsageDescription: 用于选择食物照片进行本地识别
        NSSpeechRecognitionUsageDescription: 用于将语音转文字后解析饮食记录
        NSMicrophoneUsageDescription: 用于语音输入饮食记录
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.wangk123.lightcal
  LightCalTests:
    type: bundle.unit-test
    platform: iOS
    sources: [LightCalTests]
    dependencies:
      - target: LightCal
  LightCalUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [LightCalUITests]
    dependencies:
      - target: LightCal
schemes:
  LightCal:
    build:
      targets:
        LightCal: all
        LightCalTests: [test]
        LightCalUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - LightCalTests
        - LightCalUITests
```

- [ ] **Step 3: 写 scripts/ensure-simulator.sh（下载 iOS 运行时并建 iPhone 16 模拟器）**

```bash
#!/bin/bash
set -euo pipefail
# 首次运行需下载 iOS 运行时（约数 GB，只执行一次）
if ! xcrun simctl list runtimes | grep -q "iOS"; then
  xcodebuild -downloadPlatform iOS
fi
if ! xcrun simctl list devices available | grep -q "iPhone 16 ("; then
  DEVICE_TYPE=$(xcrun simctl list devicetypes | grep -oE '"com.apple.CoreSimulator.SimDeviceType.iPhone-16[^"]*"' | head -1 | tr -d '"')
  RUNTIME_ID=$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1)
  xcrun simctl create "iPhone 16" "$DEVICE_TYPE" "$RUNTIME_ID"
fi
echo "simulator ready: $(xcrun simctl list devices available | grep 'iPhone 16 (' | head -1)"
```

```bash
chmod +x scripts/ensure-simulator.sh
```

- [ ] **Step 4: 生成工程并准备模拟器**

```bash
xcodegen generate
./scripts/ensure-simulator.sh
```

Expected: 生成 `LightCal.xcodeproj`；脚本输出 `simulator ready: iPhone 16 (...)`。

- [ ] **Step 5: 写 LightCal/App/LightCalApp.swift（临时壳，Task 16 换 RootTabView）**

```swift
import SwiftUI

@main
struct LightCalApp: App {
    var body: some Scene {
        WindowGroup {
            Text("轻卡")
                .font(.largeTitle)
                .foregroundStyle(DesignTokens.primary)
        }
    }
}
```

- [ ] **Step 6: 写 LightCal/UI/DesignTokens.swift**

```swift
import SwiftUI

/// 设计令牌：全局唯一颜色/尺寸来源（spec 7.6）
enum DesignTokens {
    static let primary = Color(hex: 0x0891B2)
    static let accent = Color(hex: 0x059669)
    static let background = Color(hex: 0xECFEFF)
    static let destructive = Color(hex: 0xDC2626)
    static let aiAmber = Color(hex: 0xD97706)
    static let targetLine = Color(hex: 0x64748B)
    static let minTouchSize: CGFloat = 44
    static let touchGap: CGFloat = 8
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
```

- [ ] **Step 7: 写 LightCalTests/SmokeTests.swift（验证测试链路）**

```swift
import XCTest
import SwiftUI
@testable import LightCal

final class SmokeTests: XCTestCase {
    func testDesignTokensAreDefined() {
        XCTAssertNotNil(DesignTokens.primary)
        XCTAssertEqual(DesignTokens.minTouchSize, 44)
    }

    func testColorHexDecoding() {
        let c = Color(hex: 0x0891B2)
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 8.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(g, 0x91 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0xB2 / 255.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 8: 跑测试验证链路通**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/SmokeTests`
Expected: `** TEST SUCCEEDED **`（两个用例 PASS）

- [ ] **Step 9: Commit**

```bash
git add project.yml scripts LightCal LightCalTests LightCalUITests
git commit -m "feat: 工程脚手架（xcodegen + 设计令牌 + 测试链路）"
```

---

### Task 2: NutritionFacts 营养快照

**Files:**
- Create: `LightCal/Models/NutritionFacts.swift`
- Test: `LightCalTests/NutritionFactsTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `struct NutritionFacts: Codable, Equatable, Sendable`，字段 `kcal/protein/fat/carb: Double`、`extras: [String: Double]`；`static func +(lhs:rhs:) -> NutritionFacts`（extras 相加合并）；`static func scaled(_ per100g: NutritionFacts, grams: Double) -> NutritionFacts`（按每 100g × 份量换算）。Task 5/7/8/9/11/16 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class NutritionFactsTests: XCTestCase {
    func testDefaultsAreZero() {
        let n = NutritionFacts()
        XCTAssertEqual(n.kcal, 0)
        XCTAssertEqual(n.protein, 0)
        XCTAssertTrue(n.extras.isEmpty)
    }

    func testAdditionMergesExtrasBySumming() {
        let a = NutritionFacts(kcal: 100, protein: 10, fat: 5, carb: 4, extras: ["fiber": 3])
        let b = NutritionFacts(kcal: 50, protein: 2, fat: 1, carb: 8, extras: ["fiber": 1, "sodium": 200])
        let sum = a + b
        XCTAssertEqual(sum.kcal, 150)
        XCTAssertEqual(sum.protein, 12)
        XCTAssertEqual(sum.extras["fiber"], 4)
        XCTAssertEqual(sum.extras["sodium"], 200)
    }

    func testScaledByGrams() {
        let per100 = NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9, extras: ["fiber": 1])
        let scaled = NutritionFacts.scaled(per100, grams: 50)
        XCTAssertEqual(scaled.kcal, 58, accuracy: 0.001)
        XCTAssertEqual(scaled.protein, 1.3, accuracy: 0.001)
        XCTAssertEqual(scaled.extras["fiber"] ?? 0, 0.5, accuracy: 0.001)
    }

    func testCodableRoundTripWithExtras() throws {
        let n = NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8, extras: ["sodium": 130])
        let data = try JSONEncoder().encode(n)
        let decoded = try JSONDecoder().decode(NutritionFacts.self, from: data)
        XCTAssertEqual(decoded, n)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/NutritionFactsTests`
Expected: FAIL，`cannot find 'NutritionFacts' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

/// 营养快照：核心字段 + 可扩展字典（spec 3.7，微营养素将来加 extras 即可，无迁移）
struct NutritionFacts: Codable, Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carb: Double = 0
    var extras: [String: Double] = [:]

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            carb: lhs.carb + rhs.carb,
            extras: lhs.extras.merging(rhs.extras) { $0 + $1 }
        )
    }

    /// 每 100g 数值 × 份量(g) 换算
    static func scaled(_ per100g: NutritionFacts, grams: Double) -> NutritionFacts {
        let factor = grams / 100.0
        return NutritionFacts(
            kcal: per100g.kcal * factor,
            protein: per100g.protein * factor,
            fat: per100g.fat * factor,
            carb: per100g.carb * factor,
            extras: per100g.extras.mapValues { $0 * factor }
        )
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LightCal/Models/NutritionFacts.swift LightCalTests/NutritionFactsTests.swift
git commit -m "feat: NutritionFacts 营养快照（核心字段+可扩展字典）"
```

---

### Task 3: 解析领域模型（MealKind / ParsedFoodItem / FoodTextParsing）

**Files:**
- Create: `LightCal/Models/ParsedFoodItem.swift`
- Test: `LightCalTests/ParsedFoodItemTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum MealKind: String, Codable, CaseIterable, Sendable`，cases `breakfast="早餐" / lunch="午餐" / dinner="晚餐" / snack="加餐"`
  - `struct ParsedFoodItem: Equatable, Sendable`，字段 `name: String, grams: Double?, count: Double?, unit: String?, meal: MealKind?`
  - `protocol FoodTextParsing: Sendable { func parse(_ text: String) async throws -> [ParsedFoodItem] }`
  - Task 4/6/13 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class ParsedFoodItemTests: XCTestCase {
    func testMealKindRawValues() {
        XCTAssertEqual(MealKind.breakfast.rawValue, "早餐")
        XCTAssertEqual(MealKind.lunch.rawValue, "午餐")
        XCTAssertEqual(MealKind.dinner.rawValue, "晚餐")
        XCTAssertEqual(MealKind.snack.rawValue, "加餐")
        XCTAssertEqual(MealKind(rawValue: "午餐"), .lunch)
    }

    func testParsedFoodItemEquatable() {
        let a = ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)
        let b = ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)
        XCTAssertEqual(a, b)
    }

    func testParsedFoodItemCodable() throws {
        let item = ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ParsedFoodItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/ParsedFoodItemTests`
Expected: FAIL，`cannot find 'MealKind' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

enum MealKind: String, Codable, CaseIterable, Sendable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"
}

/// 解析中间结果：统一承接文字/语音/拍照三种入口（spec 4）
struct ParsedFoodItem: Equatable, Codable, Sendable {
    var name: String
    var grams: Double?   // 显式克重，如 "100g鸡胸肉"
    var count: Double?   // 数量，如 "两个鸡蛋"
    var unit: String?    // 单位：个/只/碗/杯/瓶/盒/袋
    var meal: MealKind?
}

/// 文本解析协议：DeepSeek 与本地正则兜底都实现它（spec 4.2）
protocol FoodTextParsing: Sendable {
    func parse(_ text: String) async throws -> [ParsedFoodItem]
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LightCal/Models/ParsedFoodItem.swift LightCalTests/ParsedFoodItemTests.swift
git commit -m "feat: 解析领域模型（MealKind/ParsedFoodItem/FoodTextParsing）"
```

---

### Task 4: LocalRegexParser 离线正则兜底解析

**Files:**
- Create: `LightCal/Logging/TextParser/LocalRegexParser.swift`
- Test: `LightCalTests/LocalRegexParserTests.swift`

**Interfaces:**
- Consumes: `MealKind`、`ParsedFoodItem`、`FoodTextParsing`（Task 3）
- Produces: `struct LocalRegexParser: FoodTextParsing`，`func parse(_ text: String) async throws -> [ParsedFoodItem]`；`static func detectMeal(in:) -> MealKind?`、`static func parseCount(_:) -> Double?`（Task 13 管线兜底依赖）

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class LocalRegexParserTests: XCTestCase {
    func testExplicitGrams() async throws {
        let items = try await LocalRegexParser().parse("100g鸡胸肉")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertNil(items[0].count)
    }

    func testChineseCountAndUnit() async throws {
        let items = try await LocalRegexParser().parse("两个鸡蛋和一杯牛奶")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "鸡蛋")
        XCTAssertEqual(items[0].count, 2)
        XCTAssertEqual(items[0].unit, "个")
        XCTAssertEqual(items[1].name, "牛奶")
        XCTAssertEqual(items[1].count, 1)
        XCTAssertEqual(items[1].unit, "杯")
    }

    func testMealDetection() async throws {
        let items = try await LocalRegexParser().parse("晚饭吃了100克牛肉")
        XCTAssertEqual(items[0].meal, .dinner)
    }

    func testBareTextFallsBackToNameItem() async throws {
        let items = try await LocalRegexParser().parse("随便聊聊")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "随便聊聊")
        XCTAssertNil(items[0].grams)
    }

    func testEmptyTextYieldsNoItems() async throws {
        let items = try await LocalRegexParser().parse("   ")
        XCTAssertTrue(items.isEmpty)
    }

    func testParseCountMapping() {
        XCTAssertEqual(LocalRegexParser.parseCount("两"), 2)
        XCTAssertEqual(LocalRegexParser.parseCount("三"), 3)
        XCTAssertEqual(LocalRegexParser.parseCount("10"), 10)
        XCTAssertNil(LocalRegexParser.parseCount("百"))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/LocalRegexParserTests`
Expected: FAIL，`cannot find 'LocalRegexParser' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

/// 离线兜底解析器（spec 4.2）：DeepSeek 不可用时解析常见中文句式
struct LocalRegexParser: FoodTextParsing {

    static let chineseNumbers: [String: Double] = [
        "两": 2, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
    ]

    private static let mealKeywords: [(MealKind, [String])] = [
        (.breakfast, ["早饭", "早餐"]),
        (.lunch, ["午饭", "午餐", "中餐"]),
        (.dinner, ["晚饭", "晚餐"]),
        (.snack, ["夜宵", "加餐", "宵夜"])
    ]

    static func detectMeal(in text: String) -> MealKind? {
        for (meal, words) in mealKeywords where words.contains(where: { text.contains($0) }) {
            return meal
        }
        return nil
    }

    static func parseCount(_ raw: String) -> Double? {
        if let n = Double(raw) { return n }
        guard raw.count == 1, let v = chineseNumbers[raw] else { return nil }
        return v
    }

    func parse(_ text: String) async throws -> [ParsedFoodItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let meal = Self.detectMeal(in: trimmed)

        // 模式1: "100g鸡胸肉" / "100克鸡胸肉"
        let gramsPattern = #/(\d+(?:\.\d+)?)\s*(?:g|克)\s*([\p{Han}A-Za-z]+)/#
        var consumed: [Range<String.Index>] = []
        var items: [ParsedFoodItem] = []
        for match in trimmed.matches(of: gramsPattern) {
            if let grams = Double(match.1) {
                consumed.append(match.range)
                items.append(ParsedFoodItem(name: String(match.2), grams: grams, count: nil, unit: nil, meal: meal))
            }
        }

        // 模式2: "两个鸡蛋" / "2个鸡蛋" / "一碗米饭"
        let countPattern = #/([两一二三四五六七八九十\d]+(?:\.\d+)?)\s*(个|只|碗|杯|瓶|盒|袋)\s*([\p{Han}A-Za-z]+)/#
        for match in trimmed.matches(of: countPattern) {
            guard !consumed.contains(where: { $0.overlaps(match.range) }),
                  let count = Self.parseCount(String(match.1)) else { continue }
            consumed.append(match.range)
            items.append(ParsedFoodItem(name: String(match.3), grams: nil, count: count, unit: String(match.2), meal: meal))
        }

        // 模式3: 剩余文本按分隔符切成纯名称条目（无任何结构化信息时的兜底）
        var remainder = trimmed
        for range in consumed.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            remainder.removeSubrange(range)
        }
        let separators = CharacterSet(charactersIn: "，,、。;；和 　")
        let parts = remainder.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for part in parts where !part.isEmpty {
            items.append(ParsedFoodItem(name: part, grams: nil, count: nil, unit: nil, meal: meal))
        }
        return items
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`（注意：若 `testBareTextFallsBackToNameItem` 失败，检查 consumed 为空时 remainder 是否保持了原文）

- [ ] **Step 5: Commit**

```bash
git add LightCal/Logging/TextParser/LocalRegexParser.swift LightCalTests/LocalRegexParserTests.swift
git commit -m "feat: 本地正则兜底解析器"
```

---

### Task 5: 内置食物库（FoodRecord / FoodDatabase / foods.json）

**Files:**
- Create: `LightCal/FoodDatabase/FoodRecord.swift`
- Create: `LightCal/FoodDatabase/FoodDatabase.swift`
- Create: `LightCal/Resources/foods.json`
- Test: `LightCalTests/FoodDatabaseTests.swift`

**Interfaces:**
- Consumes: `NutritionFacts`（Task 2）
- Produces:
  - `struct FoodRecord: Codable, Equatable, Sendable`，字段 `name: String, aliases: [String], nutritionPer100g: NutritionFacts, defaultServingGrams: Double?`
  - `struct FoodDatabase: Sendable`，`init(foods: [FoodRecord])`、`static func load(from data: Data) throws -> FoodDatabase`、`static func loadFromBundle(_ bundle: Bundle = .main) throws -> FoodDatabase`、`func match(exact name: String) -> FoodRecord?`（名称或别名精确匹配）、`func search(_ keyword: String) -> [FoodRecord]`
  - `enum FoodDatabaseError: Error { case resourceMissing }`
  - Task 7/15 依赖。

- [ ] **Step 1: 写失败测试（用内联 JSON fixture，不依赖 bundle）**

```swift
import XCTest
@testable import LightCal

final class FoodDatabaseTests: XCTestCase {
    private let fixtureJSON = """
    {"version":1,"foods":[
      {"name":"米饭","aliases":["白米饭","大米饭"],"nutritionPer100g":{"kcal":116,"protein":2.6,"fat":0.3,"carb":25.9},"defaultServingGrams":200},
      {"name":"鸡胸肉","aliases":["鸡胸"],"nutritionPer100g":{"kcal":133,"protein":24.6,"fat":3.3,"carb":0.6}},
      {"name":"鸡蛋","aliases":[],"nutritionPer100g":{"kcal":144,"protein":13.3,"fat":8.8,"carb":2.8},"defaultServingGrams":50}
    ]}
    """

    private func makeDB() throws -> FoodDatabase {
        try FoodDatabase.load(from: Data(fixtureJSON.utf8))
    }

    func testExactNameMatch() throws {
        let db = try makeDB()
        let record = db.match(exact: "米饭")
        XCTAssertEqual(record?.nutritionPer100g.kcal, 116)
        XCTAssertEqual(record?.defaultServingGrams, 200)
    }

    func testAliasMatch() throws {
        let db = try makeDB()
        XCTAssertEqual(db.match(exact: "白米饭")?.name, "米饭")
    }

    func testNoMatchReturnsNil() throws {
        let db = try makeDB()
        XCTAssertNil(db.match(exact: "火锅"))
    }

    func testSearchByKeyword() throws {
        let db = try makeDB()
        let results = db.search("鸡")
        XCTAssertEqual(Set(results.map(\.name)), ["鸡胸肉", "鸡蛋"])
    }

    func testLoadFromBundleMissingResourceThrows() {
        let bundle = Bundle(for: BundleToken.self)  // 测试宿主 bundle，无 foods.json
        XCTAssertThrowsError(try FoodDatabase.loadFromBundle(bundle)) { error in
            XCTAssertEqual(error as? FoodDatabaseError, .resourceMissing)
        }
    }

    func testDecodeInvalidJSONThrows() {
        XCTAssertThrowsError(try FoodDatabase.load(from: Data("{\"bad\":1}".utf8)))
    }
}

private final class BundleToken {}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FoodDatabaseTests`
Expected: FAIL，`cannot find 'FoodDatabase' in scope`

- [ ] **Step 3: 写 FoodRecord.swift**

```swift
import Foundation

/// 食物模板条目：内置库与自定义食物共用（spec 3.3）
struct FoodRecord: Codable, Equatable, Sendable {
    let name: String
    let aliases: [String]
    let nutritionPer100g: NutritionFacts
    var defaultServingGrams: Double?
}

struct FoodDatabaseFile: Codable {
    let version: Int
    let foods: [FoodRecord]
}
```

- [ ] **Step 4: 写 FoodDatabase.swift**

```swift
import Foundation

enum FoodDatabaseError: Error, Equatable {
    case resourceMissing
}

struct FoodDatabase: Sendable {
    let foods: [FoodRecord]

    static func load(from data: Data) throws -> FoodDatabase {
        FoodDatabase(foods: try JSONDecoder().decode(FoodDatabaseFile.self, from: data).foods)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> FoodDatabase {
        guard let url = bundle.url(forResource: "foods", withExtension: "json") else {
            throw FoodDatabaseError.resourceMissing
        }
        return try load(from: Data(contentsOf: url))
    }

    /// 名称或别名精确匹配（营养补全第一层，spec 4.3）
    func match(exact name: String) -> FoodRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return foods.first { $0.name == trimmed || $0.aliases.contains(trimmed) }
    }

    func search(_ keyword: String) -> [FoodRecord] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        return foods.filter { $0.name.contains(k) || $0.aliases.contains(where: { $0.contains(k) }) }
    }
}
```

- [ ] **Step 5: 写 LightCal/Resources/foods.json（种子库，数值为常见参考值）**

```json
{
  "version": 1,
  "foods": [
    {"name": "米饭", "aliases": ["白米饭", "大米饭"], "nutritionPer100g": {"kcal": 116, "protein": 2.6, "fat": 0.3, "carb": 25.9}, "defaultServingGrams": 200},
    {"name": "鸡胸肉", "aliases": ["鸡胸"], "nutritionPer100g": {"kcal": 133, "protein": 24.6, "fat": 3.3, "carb": 0.6}, "defaultServingGrams": 100},
    {"name": "鸡蛋", "aliases": ["鸡蛋"], "nutritionPer100g": {"kcal": 144, "protein": 13.3, "fat": 8.8, "carb": 2.8}, "defaultServingGrams": 50},
    {"name": "牛奶", "aliases": ["纯牛奶", "鲜奶"], "nutritionPer100g": {"kcal": 65, "protein": 3.3, "fat": 3.6, "carb": 4.9}, "defaultServingGrams": 250},
    {"name": "苹果", "aliases": [], "nutritionPer100g": {"kcal": 53, "protein": 0.4, "fat": 0.2, "carb": 13.7}, "defaultServingGrams": 200},
    {"name": "香蕉", "aliases": [], "nutritionPer100g": {"kcal": 93, "protein": 1.4, "fat": 0.2, "carb": 22}, "defaultServingGrams": 120},
    {"name": "西兰花", "aliases": ["绿菜花"], "nutritionPer100g": {"kcal": 36, "protein": 4.1, "fat": 0.6, "carb": 4.3}, "defaultServingGrams": 100},
    {"name": "红薯", "aliases": ["地瓜", "番薯"], "nutritionPer100g": {"kcal": 86, "protein": 1.6, "fat": 0.1, "carb": 20.1}, "defaultServingGrams": 150},
    {"name": "燕麦", "aliases": ["燕麦片"], "nutritionPer100g": {"kcal": 377, "protein": 15, "fat": 6.7, "carb": 66}, "defaultServingGrams": 40},
    {"name": "全麦面包", "aliases": [], "nutritionPer100g": {"kcal": 246, "protein": 10.4, "fat": 3.4, "carb": 41}, "defaultServingGrams": 70},
    {"name": "牛肉", "aliases": ["瘦牛肉", "牛瘦肉"], "nutritionPer100g": {"kcal": 106, "protein": 20.2, "fat": 2.3, "carb": 1.2}, "defaultServingGrams": 100},
    {"name": "三文鱼", "aliases": ["鲑鱼"], "nutritionPer100g": {"kcal": 208, "protein": 20.4, "fat": 13.4, "carb": 0}, "defaultServingGrams": 100},
    {"name": "豆腐", "aliases": ["北豆腐"], "nutritionPer100g": {"kcal": 84, "protein": 8.1, "fat": 4.2, "carb": 4.2}, "defaultServingGrams": 100},
    {"name": "酸奶", "aliases": ["无糖酸奶"], "nutritionPer100g": {"kcal": 63, "protein": 3.5, "fat": 3.3, "carb": 4.7}, "defaultServingGrams": 100},
    {"name": "花生", "aliases": ["花生米"], "nutritionPer100g": {"kcal": 567, "protein": 25.8, "fat": 49.2, "carb": 16.1}, "defaultServingGrams": 30},
    {"name": "玉米", "aliases": ["煮玉米"], "nutritionPer100g": {"kcal": 112, "protein": 4, "fat": 1.2, "carb": 22.8}, "defaultServingGrams": 150}
  ]
}
```

- [ ] **Step 6: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add LightCal/FoodDatabase LightCal/Resources LightCalTests/FoodDatabaseTests.swift
git commit -m "feat: 内置食物库（JSON 种子数据 + 名称/别名匹配）"
```

---

### Task 6: DeepSeekClient（文本解析 API 客户端）

**Files:**
- Create: `LightCal/Logging/TextParser/URLSessionProtocol.swift`
- Create: `LightCal/Logging/TextParser/DeepSeekClient.swift`
- Test: `LightCalTests/DeepSeekClientTests.swift`

**Interfaces:**
- Consumes: `ParsedFoodItem`、`MealKind`、`FoodTextParsing`（Task 3）
- Produces:
  - `protocol URLSessionProtocol: Sendable { func data(for request: URLRequest) async throws -> (Data, URLResponse) }`（`URLSession` 已扩展遵循）
  - `struct DeepSeekConfig: Sendable { var apiKey: String; var endpoint: URL; var model: String; var timeout: TimeInterval }`
  - `enum DeepSeekError: Error, Equatable { case invalidConfiguration, badStatus(Int), decodingFailed }`
  - `final class DeepSeekClient: FoodTextParsing, Sendable`，`init(config: DeepSeekConfig, session: URLSessionProtocol = URLSession.shared)`、`static func bodyPayload(text:model:) throws -> Data`、`static func decode(_ data: Data) throws -> [ParsedFoodItem]`
  - Task 13/15 依赖。

- [ ] **Step 1: 写失败测试（含 mock session 与固定响应 fixture）**

```swift
import XCTest
@testable import LightCal

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let lock = NSLock()
    private var _callCount = 0

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); _callCount += 1; lock.unlock()
        return try await handler(request)
    }
}

final class DeepSeekClientTests: XCTestCase {
    private let config = DeepSeekConfig(
        apiKey: "test-key",
        endpoint: URL(string: "https://api.deepseek.com/chat/completions")!
    )

    private let goodPayload = """
    {"choices":[{"message":{"content":"{\\"items\\":[{\\"name\\":\\"鸡胸肉\\",\\"grams\\":100,\\"count\\":null,\\"unit\\":null,\\"meal\\":\\"午餐\\"},{\\"name\\":\\"米饭\\",\\"grams\\":null,\\"count\\":1,\\"unit\\":\\"碗\\",\\"meal\\":null}]}"}}]}
    """

    private func httpResponse() -> HTTPURLResponse {
        HTTPURLResponse(url: config.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func testDecodesItemsFromResponse() async throws {
        let session = MockURLSession { _ in (Data(self.goodPayload.utf8), self.httpResponse()) }
        let client = DeepSeekClient(config: config, session: session)
        let items = try await client.parse("午餐吃100g鸡胸肉")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertEqual(items[0].meal, .lunch)
        XCTAssertEqual(items[1].name, "米饭")
        XCTAssertEqual(items[1].unit, "碗")
    }

    func testRetriesOnceOnTransportError() async {
        var first = true
        let flaky = MockURLSession { _ in
            if first { first = false; throw URLError(.networkConnectionLost) }
            return (Data(self.goodPayload.utf8), self.httpResponse())
        }
        let client = DeepSeekClient(config: config, session: flaky)
        let items = try await client.parse("100g鸡胸肉")
        XCTAssertEqual(flaky.callCount, 2)
        XCTAssertEqual(items.count, 2)
    }

    func testBadStatusThrows() async {
        let session = MockURLSession { [config] _ in
            (Data(), HTTPURLResponse(url: config.endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let client = DeepSeekClient(config: config, session: session)
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 badStatus")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .badStatus(401))
        }
    }

    func testEmptyAPIKeyThrowsInvalidConfiguration() async {
        let client = DeepSeekClient(config: DeepSeekConfig(apiKey: ""), session: MockURLSession { _ in (Data(), self.httpResponse()) })
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 invalidConfiguration")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .invalidConfiguration)
        }
    }

    func testDecodeGarbageThrowsDecodingFailed() async {
        let session = MockURLSession { _ in (Data("not json".utf8), self.httpResponse()) }
        let client = DeepSeekClient(config: config, session: session)
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 decodingFailed")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .decodingFailed)
        }
    }

    func testBodyPayloadContainsJSONMode() throws {
        let body = try DeepSeekClient.bodyPayload(text: "两个鸡蛋", model: "deepseek-chat")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "deepseek-chat")
        let responseFormat = json?["response_format"] as? [String: String]
        XCTAssertEqual(responseFormat?["type"], "json_object")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/DeepSeekClientTests`
Expected: FAIL，`cannot find 'URLSessionProtocol' in scope`

- [ ] **Step 3: 写 URLSessionProtocol.swift**

```swift
import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}
```

- [ ] **Step 4: 写 DeepSeekClient.swift**

```swift
import Foundation

struct DeepSeekConfig: Sendable {
    var apiKey: String
    var endpoint: URL
    var model: String = "deepseek-chat"
    var timeout: TimeInterval = 10

    init(apiKey: String, endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

enum DeepSeekError: Error, Equatable {
    case invalidConfiguration
    case badStatus(Int)
    case decodingFailed
}

/// DeepSeek 文本解析客户端（spec 4.2）：严格 JSON 输出、10s 超时、失败重试一次
final class DeepSeekClient: FoodTextParsing, Sendable {
    private let config: DeepSeekConfig
    private let session: URLSessionProtocol

    init(config: DeepSeekConfig, session: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func parse(_ text: String) async throws -> [ParsedFoodItem] {
        guard !config.apiKey.isEmpty else { throw DeepSeekError.invalidConfiguration }
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.bodyPayload(text: text, model: config.model)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            (data, response) = try await session.data(for: request)  // 重试一次
        }
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.decodingFailed }
        guard (200..<300).contains(http.statusCode) else { throw DeepSeekError.badStatus(http.statusCode) }
        return try Self.decode(data)
    }

    static func bodyPayload(text: String, model: String) throws -> Data {
        let systemPrompt = """
        你是食物解析器。把用户描述的饮食拆成条目，只输出 JSON，不要输出其他内容。
        规则：食物名用中文；份量尽量换算成克（g）；无法确定克重时给出 count（数量）与 unit（个/碗/杯/瓶/盒/袋）；
        识别餐次（早餐/午餐/晚餐/加餐），无餐次信息则为 null。
        输出格式：{"items":[{"name":"鸡胸肉","grams":100,"count":null,"unit":null,"meal":"午餐"}]}
        """
        struct Payload: Encodable {
            let model: String
            let messages: [[String: String]]
            let response_format: [String: String]
            let temperature: Double
        }
        let payload = Payload(
            model: model,
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            response_format: ["type": "json_object"],
            temperature: 0
        )
        return try JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) throws -> [ParsedFoodItem] {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        struct Response: Decodable { let choices: [Choice] }
        struct ItemsWrapper: Decodable { let items: [ItemDTO] }
        struct ItemDTO: Decodable {
            let name: String
            let grams: Double?
            let count: Double?
            let unit: String?
            let meal: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let content = response.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw DeepSeekError.decodingFailed
        }
        let wrapper = try JSONDecoder().decode(ItemsWrapper.self, from: contentData)
        return wrapper.items.map {
            ParsedFoodItem(
                name: $0.name,
                grams: $0.grams,
                count: $0.count,
                unit: $0.unit,
                meal: $0.meal.flatMap { MealKind(rawValue: $0) }
            )
        }
    }
}
```

- [ ] **Step 5: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add LightCal/Logging/TextParser LightCalTests/DeepSeekClientTests.swift
git commit -m "feat: DeepSeek 解析客户端（JSON 模式+超时重试）"
```

---

### Task 7: 营养补全（三层兜底 + 份量换算）

**Files:**
- Create: `LightCal/Nutrition/NutritionCompletion.swift`
- Test: `LightCalTests/NutritionCompletionTests.swift`

**Interfaces:**
- Consumes: `NutritionFacts`（Task 2）、`ParsedFoodItem`（Task 3）、`FoodRecord`/`FoodDatabase`（Task 5）
- Produces:
  - `enum NutritionSource: String, Codable, Sendable { case builtin, custom, aiEstimated }`
  - `struct CompletedFoodItem: Equatable, Sendable { name: String, grams: Double, nutrition: NutritionFacts, source: NutritionSource }`
  - `protocol NutritionCompleting: Sendable { func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem] }`
  - `enum PortionDefaults { static let unitGrams: [String: Double]; static let fallbackGrams: Double }`
  - `final class NutritionCompletion: NutritionCompleting`，`init(database: FoodDatabase, customFoodLookup: @escaping @Sendable (String) -> FoodRecord?, estimator: @escaping @Sendable (String) async throws -> NutritionFacts)`、`static func grams(for item: ParsedFoodItem, record: FoodRecord?) -> Double`
  - Task 13/15/16 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class NutritionCompletionTests: XCTestCase {
    private let database = FoodDatabase(foods: [
        FoodRecord(name: "鸡蛋", aliases: [], nutritionPer100g: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), defaultServingGrams: 50),
        FoodRecord(name: "米饭", aliases: ["白米饭"], nutritionPer100g: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), defaultServingGrams: 200)
    ])

    func testBuiltinMatchFirst() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "白米饭", grams: 100, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].source, .builtin)
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertEqual(items[0].nutrition.kcal, 116, accuracy: 0.001)
    }

    func testCustomFoodSecond() async {
        let custom = FoodRecord(name: "老妈红烧肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 350, protein: 15, fat: 30, carb: 5), defaultServingGrams: 100)
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { name in name == "老妈红烧肉" ? custom : nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "老妈红烧肉", grams: 200, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .custom)
        XCTAssertEqual(items[0].nutrition.kcal, 700, accuracy: 0.001)
    }

    func testEstimatorThirdWithAIMark() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { name in
                XCTAssertEqual(name, "螺蛳粉")
                return NutritionFacts(kcal: 180, protein: 6, fat: 8, carb: 22)
            }
        )
        let items = await completion.complete([ParsedFoodItem(name: "螺蛳粉", grams: 100, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .aiEstimated)
        XCTAssertEqual(items[0].nutrition.kcal, 180, accuracy: 0.001)
    }

    func testEstimatorFailureFallsBackToZeroNutrition() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "神秘食物", grams: nil, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .aiEstimated)
        XCTAssertEqual(items[0].nutrition, NutritionFacts())
        XCTAssertEqual(items[0].grams, PortionDefaults.fallbackGrams)
    }

    func testGramsResolution() {
        // 显式克重优先
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡", grams: 80, count: nil, unit: nil, meal: nil), record: nil), 80)
        // 数量 × 单位默认克重
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil), record: nil), 120)
        // 数量 × 食物自带每份克重（鸡蛋 50g/个）
        let egg = database.match(exact: "鸡蛋")!
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil), record: egg), 100)
        // 只有单位无数量 → 一份
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "牛奶", grams: nil, count: nil, unit: "杯", meal: nil), record: nil), 250)
        // 无任何信息 → 兜底
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "x", grams: nil, count: nil, unit: nil, meal: nil), record: nil), PortionDefaults.fallbackGrams)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/NutritionCompletionTests`
Expected: FAIL，`cannot find 'NutritionCompletion' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

enum NutritionSource: String, Codable, Sendable {
    case builtin
    case custom
    case aiEstimated
}

/// 补全后的食物条目：确认卡片与落库使用的结构（spec 4.3）
struct CompletedFoodItem: Equatable, Sendable {
    var name: String
    var grams: Double
    var nutrition: NutritionFacts
    var source: NutritionSource
}

protocol NutritionCompleting: Sendable {
    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem]
}

/// 单位默认克重（食物无自带份量时的兜底）
enum PortionDefaults {
    static let unitGrams: [String: Double] = [
        "个": 60, "只": 60, "碗": 200, "杯": 250, "瓶": 500, "盒": 250, "袋": 100
    ]
    static let fallbackGrams: Double = 100
}

/// 三层兜底：内置库 → 自定义食物 → AI 估算（spec 4.3）
final class NutritionCompletion: NutritionCompleting {
    private let database: FoodDatabase
    private let customFoodLookup: @Sendable (String) -> FoodRecord?
    private let estimator: @Sendable (String) async throws -> NutritionFacts  // 返回每 100g 营养

    init(
        database: FoodDatabase,
        customFoodLookup: @escaping @Sendable (String) -> FoodRecord?,
        estimator: @escaping @Sendable (String) async throws -> NutritionFacts
    ) {
        self.database = database
        self.customFoodLookup = customFoodLookup
        self.estimator = estimator
    }

    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem] {
        var result: [CompletedFoodItem] = []
        for item in items {
            if let record = database.match(exact: item.name) {
                result.append(make(item: item, record: record, source: .builtin))
            } else if let record = customFoodLookup(item.name) {
                result.append(make(item: item, record: record, source: .custom))
            } else {
                let grams = Self.grams(for: item, record: nil)
                let nutrition: NutritionFacts
                if let per100 = try? await estimator(item.name) {
                    nutrition = .scaled(per100, grams: grams)
                } else {
                    nutrition = NutritionFacts()  // 估算失败：零营养占位，UI 必须让用户补全
                }
                result.append(CompletedFoodItem(name: item.name, grams: grams, nutrition: nutrition, source: .aiEstimated))
            }
        }
        return result
    }

    private func make(item: ParsedFoodItem, record: FoodRecord, source: NutritionSource) -> CompletedFoodItem {
        let grams = Self.grams(for: item, record: record)
        return CompletedFoodItem(
            name: item.name,
            grams: grams,
            nutrition: .scaled(record.nutritionPer100g, grams: grams),
            source: source
        )
    }

    /// 份量换算优先级：显式克重 → 数量×每份克重 → 单位默认 → 食物默认份量 → 100g 兜底
    static func grams(for item: ParsedFoodItem, record: FoodRecord?) -> Double {
        if let grams = item.grams { return grams }
        if let count = item.count, let unit = item.unit {
            let perUnit = record?.defaultServingGrams ?? unitGrams[unit] ?? fallbackGrams
            return count * perUnit
        }
        if let unit = item.unit {
            return unitGrams[unit] ?? fallbackGrams
        }
        return record?.defaultServingGrams ?? fallbackGrams
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LightCal/Nutrition LightCalTests/NutritionCompletionTests.swift
git commit -m "feat: 营养补全三层兜底与份量换算"
```

---

### Task 8: 营养计算器（BMR/TDEE/默认目标/饮水）

**Files:**
- Create: `LightCal/Goals/NutritionCalculator.swift`
- Test: `LightCalTests/NutritionCalculatorTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum Sex: String, Codable, Sendable { case male, female }`
  - `struct ProfileInput: Equatable, Sendable { sex: Sex, ageYears: Int, heightCm: Double, weightKg: Double, activityFactor: Double }`
  - `struct DailyTargets: Codable, Equatable, Sendable { kcal, protein, fat, carb: Double }`
  - `struct WeightSample: Equatable, Sendable { date: Date, weightKg: Double }`
  - `enum NutritionCalculator { static func bmr(_:) -> Double; static func tdee(_:) -> Double; static func defaultTargets(for:) -> DailyTargets; static func defaultWaterTargetMl(weightKg:) -> Double; static let defaultDeficitKcal = 500.0; static let proteinGramsPerKg = 1.8 }`
  - Task 9/10/12/15/18 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class NutritionCalculatorTests: XCTestCase {
    private let male = ProfileInput(sex: .male, ageYears: 30, heightCm: 175, weightKg: 70, activityFactor: 1.375)

    func testBMRMale() {
        // Mifflin-St Jeor: 10*70 + 6.25*175 - 5*30 + 5 = 1648.75
        XCTAssertEqual(NutritionCalculator.bmr(male), 1648.75, accuracy: 0.001)
    }

    func testBMRFemale() {
        let female = ProfileInput(sex: .female, ageYears: 30, heightCm: 165, weightKg: 60, activityFactor: 1.375)
        // 10*60 + 6.25*165 - 5*30 - 161 = 1320.25
        XCTAssertEqual(NutritionCalculator.bmr(female), 1320.25, accuracy: 0.001)
    }

    func testTDEEAppliesActivityFactor() {
        XCTAssertEqual(NutritionCalculator.tdee(male), 1648.75 * 1.375, accuracy: 0.001)
    }

    func testDefaultTargetsStandardCase() {
        let targets = NutritionCalculator.defaultTargets(for: male)
        XCTAssertEqual(targets.kcal, 1648.75 * 1.375 - 500, accuracy: 0.001)
        XCTAssertEqual(targets.protein, 1.8 * 70, accuracy: 0.001)
        XCTAssertGreaterThan(targets.fat, 0)
        XCTAssertGreaterThan(targets.carb, 0)
        // 三大营养素热量之和 ≈ 总热量
        let sumKcal = targets.protein * 4 + targets.fat * 9 + targets.carb * 4
        XCTAssertEqual(sumKcal, targets.kcal, accuracy: 0.001)
    }

    func testKcalFloorAtBMR() {
        // 高体重低活动：TDEE-500 可能低于 BMR → 下限保护（spec 5.1）
        let heavy = ProfileInput(sex: .male, ageYears: 50, heightCm: 170, weightKg: 60, activityFactor: 1.2)
        let targets = NutritionCalculator.defaultTargets(for: heavy)
        XCTAssertEqual(targets.kcal, NutritionCalculator.bmr(heavy), accuracy: 0.001)
    }

    func testWaterTarget() {
        XCTAssertEqual(NutritionCalculator.defaultWaterTargetMl(weightKg: 70), 2100)
    }

    func testDailyTargetsCodable() throws {
        let t = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(DailyTargets.self, from: data), t)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/NutritionCalculatorTests`
Expected: FAIL，`cannot find 'NutritionCalculator' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

enum Sex: String, Codable, Sendable {
    case male, female
}

struct ProfileInput: Equatable, Sendable {
    let sex: Sex
    let ageYears: Int
    let heightCm: Double
    let weightKg: Double
    let activityFactor: Double
}

struct DailyTargets: Codable, Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carb: Double = 0
}

/// 体重采样点：本地记录与 HealthKit 统一使用
struct WeightSample: Equatable, Sendable {
    let date: Date
    let weightKg: Double
}

enum NutritionCalculator {
    static let defaultDeficitKcal = 500.0
    static let proteinGramsPerKg = 1.8

    /// Mifflin-St Jeor（spec 5.1）
    static func bmr(_ p: ProfileInput) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.ageYears)
        return p.sex == .male ? base + 5 : base - 161
    }

    static func tdee(_ p: ProfileInput) -> Double {
        bmr(p) * p.activityFactor
    }

    /// 每日目标：热量 = max(BMR, TDEE - 500)；蛋白 1.8g/kg；脂肪 max(0.8g/kg, TDEE×25%÷9)；碳水补足剩余热量
    static func defaultTargets(for p: ProfileInput) -> DailyTargets {
        let b = bmr(p)
        let t = tdee(p)
        let kcal = max(b, t - defaultDeficitKcal)
        let protein = proteinGramsPerKg * p.weightKg
        let fat = max(0.8 * p.weightKg, t * 0.25 / 9)
        let carb = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb)
    }

    /// 饮水目标：体重 × 30 ml（spec 5.1）
    static func defaultWaterTargetMl(weightKg: Double) -> Double {
        weightKg * 30
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LightCal/Goals/NutritionCalculator.swift LightCalTests/NutritionCalculatorTests.swift
git commit -m "feat: 营养计算器（Mifflin-St Jeor BMR/TDEE/默认目标）"
```

---

### Task 9: SwiftData 模型与 DataStore

**Files:**
- Create: `LightCal/Models/SwiftDataModels.swift`
- Create: `LightCal/Models/DataStore.swift`
- Test: `LightCalTests/DataStoreTests.swift`

**Interfaces:**
- Consumes: `NutritionFacts`（Task 2）、`NutritionSource`（Task 7）、`DailyTargets`/`WeightSample`（Task 8）
- Produces:
  - `@Model final class UserProfile { sex: String, birthDate: Date, heightCm: Double, initialWeightKg: Double, activityFactor: Double }`
  - `@Model final class Goal { targetWeightKg: Double, startDate: Date, startWeightKg: Double, targets: DailyTargets, systemTargets: DailyTargets, waterTargetMl: Double, createdAt: Date }`
  - `@Model final class CustomFood { name: String, nutritionPer100g: NutritionFacts, createdAt: Date }`
  - `@Model final class FoodLogItem { date: Date, meal: String, name: String, grams: Double, nutrition: NutritionFacts, source: String, createdAt: Date }`
  - `@Model final class WaterLogItem { date: Date, amountMl: Double, createdAt: Date }`
  - `@Model final class WeightRecord { date: Date, weightKg: Double, createdAt: Date }`
  - `@MainActor final class DataStore { init(container:); static func makeInMemory() throws -> DataStore; func upsertProfile(_:); func profile() throws -> UserProfile?; func appendGoal(_:); func currentGoal() throws -> Goal?; func allGoals() throws -> [Goal]; func saveLogItems(_ items: [CompletedFoodItem], date: Date, meal: MealKind) throws; func logItems(on day: Date) throws -> [FoodLogItem]; func addWater(ml: Double, date: Date) throws; func waterItems(on day: Date) throws -> [WaterLogItem]; func daySummary(_ day: Date) throws -> DaySummary; func saveCustomFood(_:); func allCustomFoods() throws -> [CustomFood]; func deleteCustomFood(_:); func addWeight(kg: Double, date: Date) throws; func weightSamples(limit: Int) throws -> [WeightSample]; func exportJSON() throws -> Data }`
  - `struct DaySummary: Equatable { totalNutrition: NutritionFacts, waterMl: Double }`
  - Task 11/12/13/15/16/18/19 依赖。

- [ ] **Step 1: 写失败测试（内存容器）**

```swift
import XCTest
@testable import LightCal

@MainActor
final class DataStoreTests: XCTestCase {
    private func makeStore() throws -> DataStore {
        try DataStore.makeInMemory()
    }

    private func day(_ daysFromNow: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: daysFromNow, to: .now)!)
    }

    func testSaveAndQueryLogItems() throws {
        let store = try makeStore()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        try store.saveLogItems([item], date: day(), meal: .lunch)
        let items = try store.logItems(on: day())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].meal, "午餐")
        XCTAssertEqual(items[0].source, "builtin")
        // 营养快照冗余落库（spec 3.4）
        XCTAssertEqual(items[0].nutrition.kcal, 133, accuracy: 0.001)
    }

    func testDaySummaryAggregatesNutritionAndWater() throws {
        let store = try makeStore()
        let chicken = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        let rice = CompletedFoodItem(name: "米饭", grams: 100, nutrition: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), source: .builtin)
        try store.saveLogItems([chicken, rice], date: day(), meal: .dinner)
        try store.addWater(ml: 250, date: day())
        try store.addWater(ml: 500, date: day())
        let summary = try store.daySummary(day())
        XCTAssertEqual(summary.totalNutrition.kcal, 249, accuracy: 0.001)
        XCTAssertEqual(summary.totalNutrition.protein, 27.2, accuracy: 0.001)
        XCTAssertEqual(summary.waterMl, 750, accuracy: 0.001)
    }

    func testGoalVersioningKeepsHistory() throws {
        let store = try makeStore()
        let g1 = Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200), systemTargets: DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200), waterTargetMl: 2100)
        let g2 = Goal(targetWeightKg: 64, startDate: .now, startWeightKg: 69, targets: DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195), systemTargets: DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195), waterTargetMl: 2070)
        try store.appendGoal(g1)
        try store.appendGoal(g2)
        XCTAssertEqual(try store.allGoals().count, 2)
        XCTAssertEqual(try store.currentGoal()?.targetWeightKg, 64)
    }

    func testCustomFoodCRUDAndLookup() throws {
        let store = try makeStore()
        let food = CustomFood(name: "老妈红烧肉", nutritionPer100g: NutritionFacts(kcal: 350, protein: 15, fat: 30, carb: 5))
        try store.saveCustomFood(food)
        XCTAssertEqual(try store.allCustomFoods().count, 1)
        try store.deleteCustomFood(food)
        XCTAssertTrue(try store.allCustomFoods().isEmpty)
    }

    func testWeightSamplesSortedDescending() throws {
        let store = try makeStore()
        try store.addWeight(kg: 70, date: day(-3))
        try store.addWeight(kg: 69.5, date: day(-1))
        try store.addWeight(kg: 69, date: day())
        let samples = try store.weightSamples(limit: 10)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].weightKg, 69)  // 最新在前
        XCTAssertEqual(samples[2].weightKg, 70)
    }

    func testExportJSONRoundTrip() throws {
        let store = try makeStore()
        let item = CompletedFoodItem(name: "鸡蛋", grams: 100, nutrition: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), source: .builtin)
        try store.saveLogItems([item], date: day(), meal: .breakfast)
        let json = try store.exportJSON()
        XCTAssertTrue(json.count > 10)
        // 合法 JSON 即可（Task 19 会做完整导入导出格式校验）
        _ = try JSONSerialization.jsonObject(with: json)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/DataStoreTests`
Expected: FAIL，`cannot find 'DataStore' in scope`

- [ ] **Step 3: 写 SwiftDataModels.swift**

```swift
import Foundation
import SwiftData

@Model
final class UserProfile {
    var sex: String
    var birthDate: Date
    var heightCm: Double
    var initialWeightKg: Double
    var activityFactor: Double

    init(sex: String, birthDate: Date, heightCm: Double, initialWeightKg: Double, activityFactor: Double) {
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.initialWeightKg = initialWeightKg
        self.activityFactor = activityFactor
    }
}

@Model
final class Goal {
    var targetWeightKg: Double
    var startDate: Date
    var startWeightKg: Double
    var targets: DailyTargets          // 当前生效目标（可微调）
    var systemTargets: DailyTargets    // 系统计算默认值（spec 3.2 分开存）
    var waterTargetMl: Double
    var createdAt: Date

    init(targetWeightKg: Double, startDate: Date, startWeightKg: Double,
         targets: DailyTargets, systemTargets: DailyTargets, waterTargetMl: Double) {
        self.targetWeightKg = targetWeightKg
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.targets = targets
        self.systemTargets = systemTargets
        self.waterTargetMl = waterTargetMl
        self.createdAt = .now
    }
}

@Model
final class CustomFood {
    var name: String
    var nutritionPer100g: NutritionFacts
    var createdAt: Date

    init(name: String, nutritionPer100g: NutritionFacts) {
        self.name = name
        self.nutritionPer100g = nutritionPer100g
        self.createdAt = .now
    }
}

@Model
final class FoodLogItem {
    var date: Date               // 当日 0 点（startOfDay）
    var meal: String             // MealKind.rawValue
    var name: String
    var grams: Double
    var nutrition: NutritionFacts  // 快照冗余（spec 3.4）
    var source: String           // NutritionSource.rawValue
    var createdAt: Date

    init(date: Date, meal: String, name: String, grams: Double, nutrition: NutritionFacts, source: String) {
        self.date = date
        self.meal = meal
        self.name = name
        self.grams = grams
        self.nutrition = nutrition
        self.source = source
        self.createdAt = .now
    }
}

@Model
final class WaterLogItem {
    var date: Date
    var amountMl: Double
    var createdAt: Date

    init(date: Date, amountMl: Double) {
        self.date = date
        self.amountMl = amountMl
        self.createdAt = .now
    }
}

@Model
final class WeightRecord {
    var date: Date
    var weightKg: Double
    var createdAt: Date

    init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
        self.createdAt = .now
    }
}
```

- [ ] **Step 4: 写 DataStore.swift**

```swift
import Foundation
import SwiftData

struct DaySummary: Equatable {
    var totalNutrition: NutritionFacts
    var waterMl: Double
}

@MainActor
final class DataStore {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    static func makeInMemory() throws -> DataStore {
        let schema = Schema([
            UserProfile.self, Goal.self, CustomFood.self,
            FoodLogItem.self, WaterLogItem.self, WeightRecord.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return DataStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    static func makeOnDisk() throws -> DataStore {
        let schema = Schema([
            UserProfile.self, Goal.self, CustomFood.self,
            FoodLogItem.self, WaterLogItem.self, WeightRecord.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return DataStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    // MARK: - Profile

    func upsertProfile(_ profile: UserProfile) throws {
        let context = container.mainContext
        let existing = try profile()
        if let existing {
            existing.sex = profile.sex
            existing.birthDate = profile.birthDate
            existing.heightCm = profile.heightCm
            existing.initialWeightKg = profile.initialWeightKg
            existing.activityFactor = profile.activityFactor
        } else {
            context.insert(profile)
        }
        try context.save()
    }

    func profile() throws -> UserProfile? {
        try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
    }

    // MARK: - Goal（历史版本全部保留，currentGoal 取最新）

    func appendGoal(_ goal: Goal) throws {
        container.mainContext.insert(goal)
        try container.mainContext.save()
    }

    func allGoals() throws -> [Goal] {
        try container.mainContext.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func currentGoal() throws -> Goal? {
        try allGoals().first
    }

    // MARK: - 打卡

    func saveLogItems(_ items: [CompletedFoodItem], date: Date, meal: MealKind) throws {
        let startOfDay = Calendar.current.startOfDay(for: date)
        for item in items {
            container.mainContext.insert(FoodLogItem(
                date: startOfDay,
                meal: meal.rawValue,
                name: item.name,
                grams: item.grams,
                nutrition: item.nutrition,
                source: item.source.rawValue
            ))
        }
        try container.mainContext.save()
    }

    func logItems(on day: Date) throws -> [FoodLogItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try container.mainContext.fetch(FetchDescriptor<FoodLogItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func deleteLogItem(_ item: FoodLogItem) throws {
        container.mainContext.delete(item)
        try container.mainContext.save()
    }

    // MARK: - 饮水

    func addWater(ml: Double, date: Date) throws {
        container.mainContext.insert(WaterLogItem(date: Calendar.current.startOfDay(for: date), amountMl: ml))
        try container.mainContext.save()
    }

    func waterItems(on day: Date) throws -> [WaterLogItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try container.mainContext.fetch(FetchDescriptor<WaterLogItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))
    }

    // MARK: - 每日聚合（派生数据，不落库 spec 3.8）

    func daySummary(_ day: Date) throws -> DaySummary {
        let items = try logItems(on: day)
        let total = items.reduce(NutritionFacts()) { $0 + $1.nutrition }
        let water = try waterItems(on: day).reduce(0) { $0 + $1.amountMl }
        return DaySummary(totalNutrition: total, waterMl: water)
    }

    // MARK: - 自定义食物

    func saveCustomFood(_ food: CustomFood) throws {
        container.mainContext.insert(food)
        try container.mainContext.save()
    }

    func allCustomFoods() throws -> [CustomFood] {
        try container.mainContext.fetch(FetchDescriptor<CustomFood>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func deleteCustomFood(_ food: CustomFood) throws {
        container.mainContext.delete(food)
        try container.mainContext.save()
    }

    // MARK: - 体重

    func addWeight(kg: Double, date: Date) throws {
        container.mainContext.insert(WeightRecord(date: date, weightKg: kg))
        try container.mainContext.save()
    }

    func weightSamples(limit: Int = 100) throws -> [WeightSample] {
        let records = try container.mainContext.fetch(FetchDescriptor<WeightRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        return records.prefix(limit).map { WeightSample(date: $0.date, weightKg: $0.weightKg) }
    }

    // MARK: - 导出

    struct ExportDTO: Codable {
        let exportedAt: Date
        let profile: UserProfile?
        let goals: [Goal]
        let customFoods: [CustomFood]
        let logItems: [FoodLogItem]
        let waterItems: [WaterLogItem]
        let weightRecords: [WeightRecord]
    }

    func exportJSON() throws -> Data {
        let context = container.mainContext
        let dto = ExportDTO(
            exportedAt: .now,
            profile: try profile(),
            goals: try context.fetch(FetchDescriptor<Goal>()),
            customFoods: try context.fetch(FetchDescriptor<CustomFood>()),
            logItems: try context.fetch(FetchDescriptor<FoodLogItem>()),
            waterItems: try context.fetch(FetchDescriptor<WaterLogItem>()),
            weightRecords: try context.fetch(FetchDescriptor<WeightRecord>())
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }
}
```

- [ ] **Step 5: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`（若 `ExportDTO` 因 @Model 类不可 Codable 报错：给每个 @Model 类加 `Codable` 遵循并补 `CodingKeys` 排除 `persistentModelID` 之外的自动属性——@Model 类实际可遵循 Codable，Xcode 26 下 `@Model` + `Codable` 可直接工作）

- [ ] **Step 6: Commit**

```bash
git add LightCal/Models LightCalTests/DataStoreTests.swift
git commit -m "feat: SwiftData 模型与 DataStore（聚合/版本留档/导出）"
```

---

### Task 10: 线性回归 + 速率计算 + 达标预测

**Files:**
- Create: `LightCal/Goals/LinearRegression.swift`
- Create: `LightCal/Goals/RateCalculator.swift`
- Create: `LightCal/Goals/PredictionCalculator.swift`
- Test: `LightCalTests/PredictionTests.swift`

**Interfaces:**
- Consumes: `WeightSample`（Task 8）
- Produces:
  - `enum LinearRegression { static func fit(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? }`
  - `enum RateCalculator { static let kcalPerKgFat = 7700.0; static func weightTrendRateKgsPerWeek(samples: [WeightSample], now: Date, calendar: Calendar) -> Double?; static func energyTrendRateKgsPerWeek(dailyDeficits: [Double]) -> Double? }`
  - `enum PredictionCalculator { static let weightRateWeight = 0.6; static let energyRateWeight = 0.4; static func predictedRateKgsPerWeek(weightRate:energyRate:) -> Double?; static func daysToReach(currentWeightKg:targetWeightKg:rateKgsPerWeek:) -> Double?; static func scenarios(...) -> Scenarios }`
  - `struct PredictionScenarios: Equatable { trendDays, conservativeDays, targetDays: Double? }`
  - Task 16/18 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class PredictionTests: XCTestCase {
    private let calendar = Calendar.current

    private func sample(_ daysAgo: Int, _ kg: Double) -> WeightSample {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
        return WeightSample(date: date, weightKg: kg)
    }

    func testLinearRegressionKnownSlope() {
        let fit = LinearRegression.fit(points: [(0, 70), (10, 69), (20, 68)])
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.slope, -0.1, accuracy: 0.0001)
        XCTAssertEqual(fit!.intercept, 70, accuracy: 0.0001)
    }

    func testLinearRegressionTwoPoints() {
        let fit = LinearRegression.fit(points: [(0, 1), (1, 3)])
        XCTAssertEqual(fit?.slope, 2, accuracy: 0.0001)
    }

    func testLinearRegressionDegenerateReturnsNil() {
        XCTAssertNil(LinearRegression.fit(points: [(0, 5)]))
    }

    func testWeightTrendRateNeedsThreePoints() {
        XCTAssertNil(RateCalculator.weightTrendRateKgsPerWeek(samples: [sample(0, 70), sample(1, 69.9)], now: .now, calendar: calendar))
    }

    func testWeightTrendRateSlopePerWeek() {
        // 0.1 kg/天 = 0.7 kg/周
        let samples = [sample(0, 69), sample(10, 70), sample(20, 71)]
        let rate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples, now: .now, calendar: calendar)
        XCTAssertEqual(rate ?? 0, 0.7, accuracy: 0.001)
    }

    func testWeightTrendWindowIs14Days() {
        // 30 天前的老数据不参与
        let old = calendar.date(byAdding: .day, value: -30, to: .now)!
        let samples = [sample(0, 69), sample(10, 70), WeightSample(date: old, weightKg: 100)]
        let rate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples, now: .now, calendar: calendar)
        XCTAssertEqual(rate ?? 0, 0.7, accuracy: 0.001)
    }

    func testEnergyTrendRate() {
        // 日均缺口 770 kcal → 0.7 kg/周
        let rate = RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: [770, 770, 770])
        XCTAssertEqual(rate ?? 0, 0.7, accuracy: 0.001)
        XCTAssertNil(RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: []))
    }

    func testPredictedRateWeighting() {
        let rate = PredictionCalculator.predictedRateKgsPerWeek(weightRate: 0.5, energyRate: 1.0)
        XCTAssertEqual(rate ?? 0, 0.5 * 0.6 + 1.0 * 0.4, accuracy: 0.001)
        XCTAssertEqual(PredictionCalculator.predictedRateKgsPerWeek(weightRate: 0.5, energyRate: nil), 0.5)
        XCTAssertEqual(PredictionCalculator.predictedRateKgsPerWeek(weightRate: nil, energyRate: 0.4), 0.4)
        XCTAssertNil(PredictionCalculator.predictedRateKgsPerWeek(weightRate: nil, energyRate: nil))
    }

    func testDaysToReach() {
        XCTAssertEqual(PredictionCalculator.daysToReach(currentWeightKg: 70, targetWeightKg: 66.5, rateKgsPerWeek: 0.5) ?? 0, 49, accuracy: 0.001)
        XCTAssertNil(PredictionCalculator.daysToReach(currentWeightKg: 66, targetWeightKg: 66.5, rateKgsPerWeek: 0.5))  // 已达标
        XCTAssertNil(PredictionCalculator.daysToReach(currentWeightKg: 70, targetWeightKg: 65, rateKgsPerWeek: 0))      // 速率 0
    }

    func testScenarios() {
        let s = PredictionCalculator.scenarios(
            currentWeightKg: 70, targetWeightKg: 66.5,
            weightRate: 0.5, energyRate: 1.0,
            targetKcal: 1800, avgDailyExpenditureLast7d: 2300
        )
        // 趋势: 0.5*0.6+1.0*0.4=0.7 → 3.5/0.7*7 = 35 天
        XCTAssertEqual(s.trendDays ?? 0, 35, accuracy: 0.001)
        // 保守: 35/0.7 = 50 天
        XCTAssertEqual(s.conservativeDays ?? 0, 50, accuracy: 0.001)
        // 目标缺口: 2300-1800=500 → 500/7700*7=0.4545 → 3.5/0.4545*7 ≈ 53.9 天
        XCTAssertEqual(s.targetDays ?? 0, 3.5 / (500.0 / 7700 * 7) * 7, accuracy: 0.001)
    }

    func testScenariosWithoutTargetDeficit() {
        let s = PredictionCalculator.scenarios(
            currentWeightKg: 70, targetWeightKg: 66.5,
            weightRate: 0.5, energyRate: nil,
            targetKcal: 2500, avgDailyExpenditureLast7d: 2300  // 支出 < 目标 → 无目标缺口
        )
        XCTAssertNotNil(s.trendDays)
        XCTAssertNil(s.targetDays)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/PredictionTests`
Expected: FAIL，`cannot find 'LinearRegression' in scope`

- [ ] **Step 3: 写 LinearRegression.swift**

```swift
import Foundation

/// 最小二乘线性拟合（spec 5.3 体重回归与趋势线共用）
enum LinearRegression {
    static func fit(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        let n = Double(points.count)
        guard points.count >= 2 else { return nil }
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        let numerator = points.reduce(0.0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let denominator = points.reduce(0.0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard denominator > 0 else { return nil }
        let slope = numerator / denominator
        return (slope: slope, intercept: meanY - slope * meanX)
    }
}
```

- [ ] **Step 4: 写 RateCalculator.swift**

```swift
import Foundation

enum RateCalculator {
    static let kcalPerKgFat = 7700.0

    /// 体重趋势速率（kg/周）：最近 14 天、≥3 点线性回归（spec 5.3）
    static func weightTrendRateKgsPerWeek(samples: [WeightSample], now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: now) else { return nil }
        let recent = samples.filter { $0.date >= cutoff }
        guard recent.count >= 3 else { return nil }
        let sorted = recent.sorted { $0.date < $1.date }
        guard let first = sorted.first?.date else { return nil }
        let points = sorted.map { (x: $0.date.timeIntervalSince(first) / 86400, y: $0.weightKg) }
        guard let fit = LinearRegression.fit(points: points) else { return nil }
        return fit.slope * 7  // kg/天 → kg/周
    }

    /// 能量趋势速率（kg/周）：近 7 天平均缺口 ÷ 7700 × 7（spec 5.3）
    static func energyTrendRateKgsPerWeek(dailyDeficits: [Double]) -> Double? {
        guard !dailyDeficits.isEmpty else { return nil }
        let avg = dailyDeficits.reduce(0, +) / Double(dailyDeficits.count)
        return avg / kcalPerKgFat * 7
    }
}
```

- [ ] **Step 5: 写 PredictionCalculator.swift**

```swift
import Foundation

struct PredictionScenarios: Equatable {
    let trendDays: Double?        // 按当前趋势
    let conservativeDays: Double? // 保守（趋势速率 × 0.7）
    let targetDays: Double?       // 按目标缺口（严格吃满目标热量）
}

enum PredictionCalculator {
    static let weightRateWeight = 0.6
    static let energyRateWeight = 0.4

    /// 综合预测速率（spec 5.4）
    static func predictedRateKgsPerWeek(weightRate: Double?, energyRate: Double?) -> Double? {
        switch (weightRate, energyRate) {
        case let (weight?, energy?): return weight * weightRateWeight + energy * energyRateWeight
        case let (weight?, nil): return weight
        case let (nil, energy?): return energy
        case (nil, nil): return nil
        }
    }

    static func daysToReach(currentWeightKg: Double, targetWeightKg: Double, rateKgsPerWeek: Double) -> Double? {
        let remaining = currentWeightKg - targetWeightKg
        guard remaining > 0, rateKgsPerWeek > 0 else { return nil }
        return remaining / rateKgsPerWeek * 7
    }

    static func scenarios(
        currentWeightKg: Double,
        targetWeightKg: Double,
        weightRate: Double?,
        energyRate: Double?,
        targetKcal: Double,
        avgDailyExpenditureLast7d: Double
    ) -> PredictionScenarios {
        let trendRate = predictedRateKgsPerWeek(weightRate: weightRate, energyRate: energyRate)
        let trendDays = trendRate.flatMap {
            daysToReach(currentWeightKg: currentWeightKg, targetWeightKg: targetWeightKg, rateKgsPerWeek: $0)
        }
        let conservativeDays = trendDays.map { $0 / 0.7 }
        let targetDeficit = avgDailyExpenditureLast7d - targetKcal
        let targetRate = targetDeficit > 0 ? targetDeficit / RateCalculator.kcalPerKgFat * 7 : nil
        let targetDays = targetRate.flatMap {
            daysToReach(currentWeightKg: currentWeightKg, targetWeightKg: targetWeightKg, rateKgsPerWeek: $0)
        }
        return PredictionScenarios(trendDays: trendDays, conservativeDays: conservativeDays, targetDays: targetDays)
    }
}
```

- [ ] **Step 6: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add LightCal/Goals LightCalTests/PredictionTests.swift
git commit -m "feat: 速率计算与达标预测引擎（回归+三情景）"
```

---

### Task 11: 建议补充食物清单引擎

**Files:**
- Create: `LightCal/Recommendations/RecommendationEngine.swift`
- Test: `LightCalTests/RecommendationEngineTests.swift`

**Interfaces:**
- Consumes: `NutritionFacts`（Task 2）、`FoodRecord`（Task 5）
- Produces:
  - `struct GapAnalysis: Equatable { remainingKcal, proteinGap, carbGap, fatGap: Double; enum PrimaryNeed: Equatable { case protein, carb, lowFatProtein, highProteinDensity }; var primaryNeed: PrimaryNeed }`
  - `struct FoodSuggestion: Equatable { name: String, grams: Double, nutrition: NutritionFacts, reason: String }`
  - `enum RecommendationEngine { static let maxSuggestions = 3; static func suggestions(gap: GapAnalysis, candidates: [FoodRecord], eatenToday: Set<String>) -> [FoodSuggestion] }`
  - Task 16 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class RecommendationEngineTests: XCTestCase {
    private let candidates = [
        FoodRecord(name: "鸡胸肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), defaultServingGrams: 100),
        FoodRecord(name: "鸡蛋", aliases: [], nutritionPer100g: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), defaultServingGrams: 50),
        FoodRecord(name: "三文鱼", aliases: [], nutritionPer100g: NutritionFacts(kcal: 208, protein: 20.4, fat: 13.4, carb: 0), defaultServingGrams: 100),
        FoodRecord(name: "米饭", aliases: [], nutritionPer100g: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), defaultServingGrams: 200),
        FoodRecord(name: "花生", aliases: [], nutritionPer100g: NutritionFacts(kcal: 567, protein: 25.8, fat: 49.2, carb: 16.1), defaultServingGrams: 30)
    ]

    func testProteinGapRanksByProteinDensity() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        // 蛋白密度: 鸡胸肉 24.6/1.33=18.5 > 鸡蛋 13.3/1.44=9.2
        XCTAssertEqual(suggestions.first?.name, "鸡胸肉")
        XCTAssertLessThanOrEqual(suggestions.count, RecommendationEngine.maxSuggestions)
    }

    func testSuggestionCaloriesWithinRemainingBudget() {
        let gap = GapAnalysis(remainingKcal: 200, proteinGap: 100, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        for s in suggestions {
            XCTAssertLessThanOrEqual(s.nutrition.kcal, 200 + 0.001)
        }
    }

    func testEatenTodayExcluded() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: ["鸡胸肉"])
        XCTAssertFalse(suggestions.contains { $0.name == "鸡胸肉" })
    }

    func testLowFatProteinNeedExcludesFattyFoods() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 20, fatGap: 10)
        // carb 与 fat 都有缺口 → lowFatProtein
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        XCTAssertFalse(suggestions.contains { $0.name == "三文鱼" })  // 脂肪 13.4 > 3
        XCTAssertFalse(suggestions.contains { $0.name == "花生" })
    }

    func testHighProteinDensityWhenKcalNearlyUsed() {
        let gap = GapAnalysis(remainingKcal: 150, proteinGap: 28, carbGap: 30, fatGap: 10)
        XCTAssertEqual(gap.primaryNeed, .highProteinDensity)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        // 150 kcal 内蛋白质最多的应是鸡胸肉（133kcal/100g → 24.6g）
        XCTAssertEqual(suggestions.first?.name, "鸡胸肉")
    }

    func testCarbGapSelectsCarbs() {
        let gap = GapAnalysis(remainingKcal: 300, proteinGap: 0, carbGap: 60, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        XCTAssertEqual(suggestions.first?.name, "米饭")
    }

    func testGapAnalysisPrimaryNeedCases() {
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 10, carbGap: 0, fatGap: 0).primaryNeed, .protein)
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 10, carbGap: 0, fatGap: 5).primaryNeed, .lowFatProtein)
        XCTAssertEqual(GapAnalysis(remainingKcal: 100, proteinGap: 10, carbGap: 20, fatGap: 0).primaryNeed, .highProteinDensity)
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 0, carbGap: 20, fatGap: 0).primaryNeed, .carb)
        XCTAssertEqual(GapAnalysis(remainingKcal: 0, proteinGap: 0, carbGap: 0, fatGap: 0).primaryNeed, .protein)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/RecommendationEngineTests`
Expected: FAIL，`cannot find 'RecommendationEngine' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation

/// 当日实时缺口（spec 6.1）
struct GapAnalysis: Equatable {
    var remainingKcal: Double
    var proteinGap: Double
    var carbGap: Double
    var fatGap: Double

    enum PrimaryNeed: Equatable {
        case protein             // 蛋白不足且热量充足
        case carb                // 碳水不足
        case lowFatProtein       // 蛋白+碳水不足且脂肪已超 → 低脂高蛋白
        case highProteinDensity  // 热量额度紧张但蛋白不足 → 蛋白质密度优先
    }

    var primaryNeed: PrimaryNeed {
        // 判定顺序（spec 6.1）：热量额度紧张（<200 kcal）且蛋白不足 → 蛋白密度优先；
        // 否则蛋白不足时看脂肪是否已超 → 低脂高蛋白 / 普通蛋白补充；最后看碳水
        if proteinGap > 0 {
            if remainingKcal < RecommendationEngine.nearLimitKcal { return .highProteinDensity }
            return fatGap > 0 ? .lowFatProtein : .protein
        }
        if carbGap > 0 { return .carb }
        return .protein
    }
}

struct FoodSuggestion: Equatable {
    let name: String
    let grams: Double
    let nutrition: NutritionFacts
    let reason: String
}

enum RecommendationEngine {
    static let maxSuggestions = 3
    static let maxSuggestionGrams = 500.0
    static let gramStep = 10.0
    static let lowFatThresholdPer100g = 5.0   // 每100g脂肪 > 5g 不算低脂（鸡胸肉 3.3、瘦牛肉 2.3 通过；三文鱼 13.4、花生 49.2 排除）
    static let nearLimitKcal = 200.0          // 剩余热量 < 200 kcal 视为额度紧张

    /// 建议清单（spec 6.2/6.3）：候选池 = 内置库 + 自定义食物（AI 估算不进池）
    static func suggestions(gap: GapAnalysis, candidates: [FoodRecord], eatenToday: Set<String>) -> [FoodSuggestion] {
        let need = gap.primaryNeed
        let isCarbNeed = (need == .carb)

        let scored: [(record: FoodRecord, score: Double, grams: Double)] = candidates.compactMap { record in
            // 排除当日已吃的
            guard !eatenToday.contains(record.name),
                  record.aliases.allSatisfy({ !eatenToday.contains($0) }) else { return nil }

            let per100 = record.nutritionPer100g
            let nutrientPer100 = isCarbNeed ? per100.carb : per100.protein
            guard nutrientPer100 > 0 else { return nil }

            // 场景过滤：低脂场景排除高脂食物
            if need == .lowFatProtein && per100.fat > lowFatThresholdPer100g { return nil }

            // 打分：营养素密度（每 kcal 克数 × 100）
            let score = nutrientPer100 / max(per100.kcal, 1) * 100

            // 满足缺口所需克重；再受剩余热量额度约束取较小值（spec 6.3），
            // 向下取整到 10g（热量预算因此天然不超）
            let gapToMeet = isCarbNeed ? gap.carbGap : gap.proteinGap
            let neededGrams = gapToMeet / nutrientPer100 * 100
            guard neededGrams > 0 else { return nil }
            let kcalPerGram = per100.kcal / 100
            let maxGramsByKcal = kcalPerGram > 0 ? gap.remainingKcal / kcalPerGram : maxSuggestionGrams
            let grams = min(min(neededGrams, maxGramsByKcal), maxSuggestionGrams)
            let rounded = max(floor(grams / gramStep) * gramStep, gramStep)
            return (record, score, rounded)
        }
        .sorted { $0.score > $1.score }
        .prefix(maxSuggestions)

        return scored.map { entry in
            FoodSuggestion(
                name: entry.record.name,
                grams: entry.grams,
                nutrition: .scaled(entry.record.nutritionPer100g, grams: entry.grams),
                reason: isCarbNeed ? "补充碳水缺口" : "补充蛋白质缺口"
            )
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LightCal/Recommendations LightCalTests/RecommendationEngineTests.swift
git commit -m "feat: 建议清单引擎（密度打分+额度约束+排除规则）"
```

---

### Task 12: HealthKitService

**Files:**
- Create: `LightCal/HealthKitService/HealthKitService.swift`
- Test: `LightCalTests/HealthKitServiceTests.swift`

**Interfaces:**
- Consumes: `WeightSample`（Task 8）
- Produces:
  - `protocol HealthKitServing: Sendable { func requestAuthorization() async throws; func activeEnergyKcal(on day: Date) async throws -> Double; func saveWeight(kg: Double, date: Date) async throws; func saveWater(ml: Double, date: Date) async throws; func latestWeightKg() async throws -> Double?; func weights(limit: Int) async throws -> [WeightSample] }`
  - `final class HealthKitService: HealthKitServing`
  - `enum HealthKitError: Error { case unavailable, notDetermined }`
  - Task 13/15/16 依赖。

- [ ] **Step 1: 写失败测试（验证类型映射与错误构造，真机行为走手工清单）**

```swift
import XCTest
import HealthKit
@testable import LightCal

final class HealthKitServiceTests: XCTestCase {
    // 模拟器环境无法稳定授权，本任务单测覆盖：类型标识映射、错误枚举、协议可被 mock（Task 13 的管线测试使用 MockHealthKit）

    func testQuantityTypeIdentifiers() {
        XCTAssertEqual(HealthKitService.activeEnergyType.identifier, HKQuantityTypeIdentifier.activeEnergyBurned.rawValue)
        XCTAssertEqual(HealthKitService.bodyMassType.identifier, HKQuantityTypeIdentifier.bodyMass.rawValue)
        XCTAssertEqual(HealthKitService.waterType.identifier, HKQuantityTypeIdentifier.dietaryWater.rawValue)
    }

    func testHealthKitErrorEquatable() {
        XCTAssertEqual(HealthKitError.unavailable, .unavailable)
        XCTAssertEqual(HealthKitError.notDetermined, .notDetermined)
    }
}

/// 供管线测试复用的 mock（Task 13 用）
final class MockHealthKit: HealthKitServing, @unchecked Sendable {
    var activeEnergy: [String: Double] = [:]
    var weightsToReturn: [WeightSample] = []
    var latestWeight: Double?
    var savedWeights: [(kg: Double, date: Date)] = []
    var savedWaters: [(ml: Double, date: Date)] = []
    var authorizationError: Error?

    func requestAuthorization() async throws {
        if let authorizationError { throw authorizationError }
    }

    func activeEnergyKcal(on day: Date) async throws -> Double {
        let key = ISO8601DateFormatter().string(from: day)
        return activeEnergy[key] ?? 0
    }

    func saveWeight(kg: Double, date: Date) async throws { savedWeights.append((kg, date)) }
    func saveWater(ml: Double, date: Date) async throws { savedWaters.append((ml, date)) }
    func latestWeightKg() async throws -> Double? { latestWeight }
    func weights(limit: Int) async throws -> [WeightSample] { Array(weightsToReturn.prefix(limit)) }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/HealthKitServiceTests`
Expected: FAIL，`cannot find 'HealthKitService' in scope`

- [ ] **Step 3: 写实现**

```swift
import Foundation
import HealthKit

enum HealthKitError: Error, Equatable {
    case unavailable      // HealthKit 在当前设备不可用
    case notDetermined    // 未授权（UI 应先 requestAuthorization）
}

protocol HealthKitServing: Sendable {
    func requestAuthorization() async throws
    func activeEnergyKcal(on day: Date) async throws -> Double
    func saveWeight(kg: Double, date: Date) async throws
    func saveWater(ml: Double, date: Date) async throws
    func latestWeightKg() async throws -> Double?
    func weights(limit: Int) async throws -> [WeightSample]
}

/// HealthKit 读写封装（spec 2/5.2/12）：运动消耗读取、体重/饮水写回
final class HealthKitService: HealthKitServing, Sendable {
    private let store: HKHealthStore

    static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    static let bodyMassType = HKQuantityType(.bodyMass)
    static let waterType = HKQuantityType(.dietaryWater)

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let types: Set<HKSampleType> = [Self.activeEnergyType, Self.bodyMassType, Self.waterType]
        try await store.requestAuthorization(toShare: types, read: types)
    }

    func activeEnergyKcal(on day: Date) async throws -> Double {
        guard isAvailable else { throw HealthKitError.unavailable }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: Self.activeEnergyType, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }

    func saveWeight(kg: Double, date: Date) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(
            type: Self.bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date
        )
        try await store.save(sample)
    }

    func saveWater(ml: Double, date: Date) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
            start: date, end: date
        )
        try await store.save(sample)
    }

    func latestWeightKg() async throws -> Double? {
        try await weights(limit: 1).first?.weightKg
    }

    func weights(limit: Int) async throws -> [WeightSample] {
        guard isAvailable else { throw HealthKitError.unavailable }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMassType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.results(for: store)
        return samples.map { sample in
            WeightSample(date: sample.startDate, weightKg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 真机手工验证（写入计划记录，实现在 Task 20 前完成）**

iPhone 真机上：授权弹窗出现并允许；Apple Watch 佩戴时 `activeEnergyKcal` 返回非 0；录入体重后健康 App 可见；`saveWater` 后健康 App 饮水可见。**本步骤不阻塞 commit。**

- [ ] **Step 6: Commit**

```bash
git add LightCal/HealthKitService LightCalTests/HealthKitServiceTests.swift
git commit -m "feat: HealthKit 服务（活动消耗/体重/饮水）"
```

---

### Task 13: 录入管线编排（LoggingPipeline）

**Files:**
- Create: `LightCal/Logging/LoggingPipeline.swift`
- Test: `LightCalTests/LoggingPipelineTests.swift`

**Interfaces:**
- Consumes: `ParsedFoodItem`/`FoodTextParsing`（Task 3）、`CompletedFoodItem`/`NutritionCompleting`（Task 7）
- Produces:
  - `protocol FoodPhotoRecognizing: Sendable { func recognize(_ imageData: Data) async throws -> [ParsedFoodItem] }`
  - `struct LogDraft: Equatable, Sendable { items: [CompletedFoodItem], originalText: String? }`
  - `protocol LoggingPipelining: Sendable { func process(text: String) async throws -> LogDraft; func process(photoData: Data) async throws -> LogDraft }`
  - `final class LoggingPipeline: LoggingPipelining`，`init(textParser:fallbackParser:photoRecognizer:completion:)`
  - `enum LoggingPipelineError: Error, Equatable { case emptyInput, photoRecognitionFailed }`
  - Task 15/16/17 依赖。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class MockTextParser: FoodTextParsing, @unchecked Sendable {
    var handler: @Sendable (String) async throws -> [ParsedFoodItem]
    init(handler: @escaping @Sendable (String) async throws -> [ParsedFoodItem]) { self.handler = handler }
    func parse(_ text: String) async throws -> [ParsedFoodItem] { try await handler(text) }
}

final class MockPhotoRecognizer: FoodPhotoRecognizing, @unchecked Sendable {
    var handler: @Sendable (Data) async throws -> [ParsedFoodItem]
    init(handler: @escaping @Sendable (Data) async throws -> [ParsedFoodItem]) { self.handler = handler }
    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem] { try await handler(imageData) }
}

final class MockCompletion: NutritionCompleting, @unchecked Sendable {
    var handler: @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem]
    init(handler: @escaping @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem]) { self.handler = handler }
    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem] { await handler(items) }
}

final class LoggingPipelineTests: XCTestCase {
    private let parsed = [ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)]
    private let completed = [CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133), source: .builtin)]

    private func makePipeline(
        text: @escaping @Sendable (String) async throws -> [ParsedFoodItem] = { _ in [] },
        photo: @escaping @Sendable (Data) async throws -> [ParsedFoodItem] = { _ in [] },
        completion: @escaping @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem] = { _ in [] }
    ) -> LoggingPipeline {
        LoggingPipeline(
            textParser: MockTextParser(handler: text),
            fallbackParser: MockTextParser(handler: text),
            photoRecognizer: MockPhotoRecognizer(handler: photo),
            completion: MockCompletion(handler: completion)
        )
    }

    func testTextHappyPath() async throws {
        let pipeline = makePipeline(
            text: { text in
                XCTAssertEqual(text, "100g鸡胸肉")
                return self.parsed
            },
            completion: { items in
                XCTAssertEqual(items, self.parsed)
                return self.completed
            }
        )
        let draft = try await pipeline.process(text: "100g鸡胸肉")
        XCTAssertEqual(draft.items, self.completed)
        XCTAssertEqual(draft.originalText, "100g鸡胸肉")
    }

    func testTextParserFailureFallsBackToFallbackParser() async throws {
        var primaryCalls = 0
        var fallbackCalls = 0
        let primary = MockTextParser { _ in
            primaryCalls += 1
            throw DeepSeekError.badStatus(500)
        }
        let fallback = MockTextParser { _ in
            fallbackCalls += 1
            return self.parsed
        }
        let pipeline = LoggingPipeline(
            textParser: primary, fallbackParser: fallback,
            photoRecognizer: MockPhotoRecognizer(handler: { _ in [] }),
            completion: MockCompletion(handler: { _ in self.completed })
        )
        let draft = try await pipeline.process(text: "100g鸡胸肉")
        XCTAssertEqual(primaryCalls, 1)
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(draft.items.count, 1)
    }

    func testBothParsersFailPreservesOriginalText() async throws {
        let pipeline = makePipeline(
            text: { _ in throw DeepSeekError.decodingFailed },
            completion: { _ in [] }
        )
        let draft = try await pipeline.process(text: "一碗神秘的汤")
        XCTAssertEqual(draft.items, [])
        XCTAssertEqual(draft.originalText, "一碗神秘的汤")  // 输入永不丢失（spec 4.2）
    }

    func testEmptyInputThrows() async {
        let pipeline = makePipeline()
        do {
            _ = try await pipeline.process(text: "   ")
            XCTFail("应当抛出 emptyInput")
        } catch let error as LoggingPipelineError {
            XCTAssertEqual(error, .emptyInput)
        }
    }

    func testPhotoSuccessPassesThroughCompletion() async throws {
        let imageData = Data([0xFF, 0xD8])
        let pipeline = makePipeline(
            photo: { data in
                XCTAssertEqual(data, imageData)
                return self.parsed
            },
            completion: { _ in self.completed }
        )
        let draft = try await pipeline.process(photoData: imageData)
        XCTAssertEqual(draft.items, self.completed)
        XCTAssertNil(draft.originalText)
    }

    func testPhotoFailureThrows() async {
        let pipeline = makePipeline(photo: { _ in throw URLError(.cannotDecodeContentData) })
        do {
            _ = try await pipeline.process(photoData: Data())
            XCTFail("应当抛出 photoRecognitionFailed")
        } catch let error as LoggingPipelineError {
            XCTAssertEqual(error, .photoRecognitionFailed)
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/LoggingPipelineTests`
Expected: FAIL，`cannot find 'LoggingPipeline' in scope`（Task 14 的 Vision/语音封装随后完成，两个任务一起跑测试、一起提交，见 Task 14 Step 7）

- [ ] **Step 3: 写实现**

```swift
import Foundation

protocol FoodPhotoRecognizing: Sendable {
    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem]
}

/// 确认卡片数据（spec 4.4）：AI/识别结果先到这里，不直接落库
struct LogDraft: Equatable, Sendable {
    var items: [CompletedFoodItem]
    var originalText: String?
}

enum LoggingPipelineError: Error, Equatable {
    case emptyInput
    case photoRecognitionFailed
}

protocol LoggingPipelining: Sendable {
    func process(text: String) async throws -> LogDraft
    func process(photoData: Data) async throws -> LogDraft
}

/// 录入管线（spec 4）：文字/语音走 textParser → fallbackParser 降级链；拍照走 photoRecognizer
final class LoggingPipeline: LoggingPipelining {
    private let textParser: FoodTextParsing
    private let fallbackParser: FoodTextParsing
    private let photoRecognizer: FoodPhotoRecognizing
    private let completion: NutritionCompleting

    init(
        textParser: FoodTextParsing,
        fallbackParser: FoodTextParsing,
        photoRecognizer: FoodPhotoRecognizing,
        completion: NutritionCompleting
    ) {
        self.textParser = textParser
        self.fallbackParser = fallbackParser
        self.photoRecognizer = photoRecognizer
        self.completion = completion
    }

    func process(text: String) async throws -> LogDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LoggingPipelineError.emptyInput }

        let parsed: [ParsedFoodItem]
        do {
            parsed = try await textParser.parse(trimmed)
        } catch {
            parsed = (try? await fallbackParser.parse(trimmed))
                ?? [ParsedFoodItem(name: trimmed, grams: nil, count: nil, unit: nil, meal: nil)]
        }
        let items = await completion.complete(parsed)
        return LogDraft(items: items, originalText: trimmed)
    }

    func process(photoData: Data) async throws -> LogDraft {
        let parsed: [ParsedFoodItem]
        do {
            parsed = try await photoRecognizer.recognize(photoData)
        } catch {
            throw LoggingPipelineError.photoRecognitionFailed  // UI 降级为文字录入
        }
        let items = await completion.complete(parsed)
        return LogDraft(items: items, originalText: nil)
    }
}
```

- [ ] **Step 4: 完成 Task 14 后一起运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit（Task 13 + 14 一起提交）**

```bash
git add LightCal/Logging LightCalTests/LoggingPipelineTests.swift LightCalTests/VisionSpeechTests.swift
git commit -m "feat: 录入管线编排 + Vision/语音封装"
```

---

### Task 14: Vision 食物识别 + 语音流式转写封装

**Files:**
- Create: `LightCal/Logging/PhotoRecognizer/VisionFoodRecognizer.swift`
- Create: `LightCal/Logging/SpeechTranscriber/SpeechTranscriber.swift`
- Test: `LightCalTests/VisionSpeechTests.swift`

**Interfaces:**
- Consumes: `FoodPhotoRecognizing`（Task 13）、`ParsedFoodItem`（Task 3）
- Produces:
  - `final class VisionFoodRecognizer: FoodPhotoRecognizing, @unchecked Sendable`，`static func localizedName(_ identifier: String) -> String`、`static func makeCGImage(_ data: Data) -> CGImage?`
  - `enum VisionFoodRecognizerError: Error, Equatable { case invalidImage, noFoodDetected }`
  - `protocol SpeechTranscribing: Sendable { func transcribeLive() async throws -> String }`
  - `final class SpeechTranscriber: SpeechTranscribing, @unchecked Sendable`、`enum SpeechTranscriberError: Error, Equatable { case unavailable }`
  - Task 16/17 依赖。语音音频全程内存流式（spec 4.6，不落盘）。

- [ ] **Step 1: 写失败测试（可自动化部分；真机行为走手工清单）**

```swift
import XCTest
@testable import LightCal

final class VisionSpeechTests: XCTestCase {
    func testLabelMappingKnownFoods() {
        XCTAssertEqual(VisionFoodRecognizer.localizedName("Rice"), "米饭")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("chicken"), "鸡肉")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("sweet potato"), "红薯")
        XCTAssertEqual(VisionFoodRecognizer.localizedName("SomeUnknownThing"), "SomeUnknownThing")
    }

    func testCGImageFromPNGData() throws {
        // 1x1 透明 PNG
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let data = Data(base64Encoded: pngBase64)!
        XCTAssertNotNil(VisionFoodRecognizer.makeCGImage(data))
    }

    func testCGImageFromGarbageReturnsNil() {
        XCTAssertNil(VisionFoodRecognizer.makeCGImage(Data([0x00, 0x01])))
    }

    func testSpeechErrorEquatable() {
        XCTAssertEqual(SpeechTranscriberError.unavailable, .unavailable)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/VisionSpeechTests`
Expected: FAIL，`cannot find 'VisionFoodRecognizer' in scope`

- [ ] **Step 3: 写 VisionFoodRecognizer.swift**

```swift
import Foundation
import Vision
import ImageIO

enum VisionFoodRecognizerError: Error, Equatable {
    case invalidImage
    case noFoodDetected
}

/// 本地 Vision 食物识别（spec 4.1）：免费、离线、照片不出设备
final class VisionFoodRecognizer: FoodPhotoRecognizing, @unchecked Sendable {
    private static let labelMap: [String: String] = [
        "rice": "米饭", "chicken": "鸡肉", "egg": "鸡蛋", "apple": "苹果",
        "banana": "香蕉", "milk": "牛奶", "noodle": "面条", "bread": "面包",
        "broccoli": "西兰花", "tofu": "豆腐", "beef": "牛肉", "salmon": "三文鱼",
        "yogurt": "酸奶", "corn": "玉米", "sweet potato": "红薯", "oatmeal": "燕麦",
        "pork": "猪肉", "shrimp": "虾", "orange": "橙子"
    ]

    static func localizedName(_ identifier: String) -> String {
        labelMap[identifier.lowercased()] ?? identifier
    }

    static func makeCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem] {
        guard let cgImage = Self.makeCGImage(imageData) else {
            throw VisionFoodRecognizerError.invalidImage
        }
        let request = VNRecognizeFoodInSceneRequest()
        request.preferBackgroundProcessing = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let top = observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
        guard !top.isEmpty else { throw VisionFoodRecognizerError.noFoodDetected }
        return top.map { observation in
            let name = observation.labels
                .sorted { $0.confidence > $1.confidence }
                .first
                .map { Self.localizedName($0.identifier) } ?? ""
            // 份量未知：确认卡片按默认份量填（spec 4.1）
            return ParsedFoodItem(name: name, grams: nil, count: nil, unit: nil, meal: nil)
        }
    }
}
```

- [ ] **Step 4: 写 SpeechTranscriber.swift（流式、音频不落盘）**

```swift
import Foundation
import Speech
import AVFoundation

enum SpeechTranscriberError: Error, Equatable {
    case unavailable
}

protocol SpeechTranscribing: Sendable {
    func transcribeLive() async throws -> String
}

/// 设备端语音转写（spec 4.2/4.6）：AVAudioEngine 流式送入，音频不落盘
final class SpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let locale: Locale

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
    }

    func transcribeLive() async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriberError.unavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var finished = false
                var lastText = ""
                recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let error {
                        finished = true
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result {
                        lastText = result.bestTranscription.formattedString
                        if result.isFinal {
                            finished = true
                            continuation.resume(returning: lastText)
                        }
                    }
                }
            }
        } onCancel: {
            engine.stop()
            input.removeTap(onBus: 0)
            recognizer.recognitionTask(with: request) { _, _ in }  // 触发错误以释放等待
        }
    }
}
```

- [ ] **Step 5: 运行确认通过（Task 13 + 14 一起）**

Run:
```bash
xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/VisionSpeechTests -only-testing:LightCalTests/LoggingPipelineTests
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: 真机手工验证清单（不阻塞 commit）**

拍照：相机拍一份鸡胸肉+米饭 → 识别出候选 → 确认卡片可见；语音：长按说话「一碗米饭两个鸡蛋」→ 转写文本 → 解析为 2 条。

- [ ] **Step 7: Commit（Task 13 + 14 一起）**

```bash
git add LightCal/Logging LightCalTests/LoggingPipelineTests.swift LightCalTests/VisionSpeechTests.swift
git commit -m "feat: 录入管线编排 + Vision/语音封装"
```

---

### Task 15: 依赖装配（AppContainer）+ 首次建档向导（Onboarding）

**Files:**
- Create: `LightCal/App/AppContainer.swift`
- Create: `LightCal/UI/Onboarding/OnboardingViewModel.swift`
- Create: `LightCal/UI/Onboarding/OnboardingView.swift`
- Modify: `LightCal/App/LightCalApp.swift`（按需进入 Onboarding 或 RootTabView 占位）
- Test: `LightCalTests/OnboardingViewModelTests.swift`

**Interfaces:**
- Consumes: Task 2/3/5/6/7/8/9/12/13/14 全部产物
- Produces:
  - `@MainActor final class AppContainer`：`static let shared: AppContainer`；属性 `store: DataStore, database: FoodDatabase, pipeline: LoggingPipelining, healthKit: HealthKitServing, speechTranscriber: SpeechTranscribing, visionRecognizer: FoodPhotoRecognizing`；`static func bootstrap() -> AppContainer`（支持 `--uitest` 参数时用内存库+种子数据）
  - `@MainActor @Observable final class OnboardingViewModel`：`var sex/ birthDate/ heightCm/ initialWeightKg/ targetWeightKg/ activityFactor`；`var profileInput: ProfileInput`；`var defaultTargets: DailyTargets`；`var defaultWaterMl: Double`；`func save(into store: DataStore) throws`
  - `struct OnboardingView: View`（表单 + 保存按钮，accessibilityIdentifier 供 UI 测试）
  - Task 16-19 依赖。

- [ ] **Step 1: 写失败测试（ViewModel 逻辑）**

```swift
import XCTest
@testable import LightCal

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testProfileInputDerived() {
        let vm = OnboardingViewModel()
        vm.sex = .female
        vm.heightCm = 165
        vm.initialWeightKg = 60
        vm.activityFactor = 1.2
        vm.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        XCTAssertEqual(vm.profileInput.sex, .female)
        XCTAssertEqual(vm.profileInput.ageYears, 30)
        XCTAssertEqual(vm.profileInput.heightCm, 165)
        XCTAssertEqual(vm.profileInput.weightKg, 60)
    }

    func testDefaultTargetsFromViewModel() {
        let vm = OnboardingViewModel()
        vm.initialWeightKg = 70
        XCTAssertEqual(vm.defaultTargets.protein, 1.8 * 70, accuracy: 0.001)
        XCTAssertEqual(vm.defaultWaterMl, 2100)
    }

    func testSavePersistsProfileAndGoal() throws {
        let store = try DataStore.makeInMemory()
        let vm = OnboardingViewModel()
        vm.targetWeightKg = 65
        try vm.save(into: store)
        XCTAssertNotNil(try store.profile())
        let goal = try store.currentGoal()
        XCTAssertEqual(goal?.targetWeightKg, 65)
        XCTAssertEqual(goal?.startWeightKg, vm.initialWeightKg)
        XCTAssertEqual(goal?.targets, vm.defaultTargets)          // 当前目标 = 系统默认（未微调）
        XCTAssertEqual(goal?.systemTargets, vm.defaultTargets)    // 默认值分开留档
        XCTAssertEqual(goal?.waterTargetMl, 2100)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/OnboardingViewModelTests`
Expected: FAIL，`cannot find 'OnboardingViewModel' in scope`

- [ ] **Step 3: 写 AppContainer.swift**

```swift
import Foundation
import SwiftUI

/// 依赖装配（spec 8.2 原则：UI 只依赖协议）
@MainActor
final class AppContainer {
    static let shared = AppContainer.bootstrap()

    let store: DataStore
    let database: FoodDatabase
    let pipeline: LoggingPipelining
    let healthKit: HealthKitServing
    let speechTranscriber: SpeechTranscribing
    let visionRecognizer: FoodPhotoRecognizing

    private init(store: DataStore, database: FoodDatabase) {
        self.store = store
        self.database = database

        let apiKey = UserDefaults.standard.string(forKey: "deepseekApiKey") ?? ""
        let deepSeekClient = DeepSeekClient(config: DeepSeekConfig(apiKey: apiKey))
        let fallbackParser = LocalRegexParser()

        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { [store] name in
                MainActor.assumeIsolated {
                    let custom = try? store.allCustomFoods()
                    let matched = custom?.first { $0.name == name }
                    return matched.map { FoodRecord(name: $0.name, aliases: [], nutritionPer100g: $0.nutritionPer100g, defaultServingGrams: 100) }
                }
            },
            estimator: { name in
                // AI 估算：解析器顺带估算每 100g 营养
                let prompt = "估算食物「\(name)」每 100 克的热量(kcal)、蛋白质(g)、脂肪(g)、碳水(g)。只输出 JSON：{\"kcal\":0,\"protein\":0,\"fat\":0,\"carb\":0}"
                let client = DeepSeekClient(config: DeepSeekConfig(apiKey: UserDefaults.standard.string(forKey: "deepseekApiKey") ?? ""))
                // 走一次性 completion 调用：直接把 prompt 当文本解析不可行，改为独立估算端点逻辑
                // 实现：调用 DeepSeekClient 的 chat 接口，从 JSON 里取 4 个数字
                return try await Self.estimateNutrition(client: client, prompt: prompt)
            }
        )

        let vision = VisionFoodRecognizer()
        self.pipeline = LoggingPipeline(
            textParser: deepSeekClient,
            fallbackParser: fallbackParser,
            photoRecognizer: vision,
            completion: completion
        )
        self.healthKit = HealthKitService()
        self.speechTranscriber = SpeechTranscriber()
        self.visionRecognizer = vision
    }

    static func bootstrap() -> AppContainer {
        let database = (try? FoodDatabase.loadFromBundle()) ?? FoodDatabase(foods: [])
        let store: DataStore
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            store = (try? DataStore.makeInMemory()) ?? (try! DataStore.makeOnDisk())
            seedForUITest(store: store)
        } else {
            store = (try? DataStore.makeOnDisk()) ?? (try! DataStore.makeInMemory())
        }
        return AppContainer(store: store, database: database)
    }

    private static func seedForUITest(store: DataStore) {
        let profile = UserProfile(sex: "male", birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now)!, heightCm: 175, initialWeightKg: 70, activityFactor: 1.375)
        try? store.upsertProfile(profile)
        let targets = NutritionCalculator.defaultTargets(for: ProfileInput(sex: .male, ageYears: 30, heightCm: 175, weightKg: 70, activityFactor: 1.375))
        let goal = Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100)
        try? store.appendGoal(goal)
    }

    private static func estimateNutrition(client: DeepSeekClient, prompt: String) async throws -> NutritionFacts {
        // 复用 DeepSeek chat 接口做营养估算：解析 JSON 数字
        struct EstimationDTO: Decodable { let kcal: Double; let protein: Double; let fat: Double; let carb: Double }
        // DeepSeekClient.decode 面向食物条目；这里直接内联一次简单调用
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(UserDefaults.standard.string(forKey: "deepseekApiKey") ?? "")", forHTTPHeaderField: "Authorization")
        struct Payload: Encodable {
            let model: String
            let messages: [[String: String]]
            let response_format: [String: String]
            let temperature: Double
        }
        let payload = Payload(
            model: "deepseek-chat",
            messages: [["role": "user", "content": prompt]],
            response_format: ["type": "json_object"],
            temperature: 0
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        struct Response: Decodable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else { throw DeepSeekError.decodingFailed }
        let dto = try JSONDecoder().decode(EstimationDTO.self, from: contentData)
        return NutritionFacts(kcal: dto.kcal, protein: dto.protein, fat: dto.fat, carb: dto.carb)
    }
}
```

> 注意：`customFoodLookup` 闭包内的 `MainActor.assumeIsolated` 依赖 Swift 6 闭包在 MainActor 上下文执行；若编译器报隔离错误，改为把 `DataStore` 查询结果以参数传入 `NutritionCompletion.complete(items:customFoods:)`。以编译通过为准，接口签名保持 `complete(_:)` 不变。

- [ ] **Step 4: 写 OnboardingViewModel.swift**

```swift
import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var sex: Sex = .male
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    var heightCm: Double = 175
    var initialWeightKg: Double = 70
    var targetWeightKg: Double = 65
    var activityFactor: Double = 1.375

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    var profileInput: ProfileInput {
        ProfileInput(sex: sex, ageYears: ageYears, heightCm: heightCm, weightKg: initialWeightKg, activityFactor: activityFactor)
    }

    var defaultTargets: DailyTargets {
        NutritionCalculator.defaultTargets(for: profileInput)
    }

    var defaultWaterMl: Double {
        NutritionCalculator.defaultWaterTargetMl(weightKg: initialWeightKg)
    }

    /// 保存档案 + 首个目标版本（spec 3.2：目标可后续修改并留档）
    func save(into store: DataStore) throws {
        let profile = UserProfile(
            sex: sex.rawValue,
            birthDate: birthDate,
            heightCm: heightCm,
            initialWeightKg: initialWeightKg,
            activityFactor: activityFactor
        )
        try store.upsertProfile(profile)
        let targets = defaultTargets
        try store.appendGoal(Goal(
            targetWeightKg: targetWeightKg,
            startDate: .now,
            startWeightKg: initialWeightKg,
            targets: targets,
            systemTargets: targets,
            waterTargetMl: defaultWaterMl
        ))
    }
}
```

- [ ] **Step 5: 写 OnboardingView.swift**

```swift
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss
    var store: DataStore

    var body: some View {
        NavigationStack {
            Form {
                Section("身体档案") {
                    Picker("性别", selection: $viewModel.sex) {
                        Text("男").tag(Sex.male)
                        Text("女").tag(Sex.female)
                    }
                    DatePicker("出生日期", selection: $viewModel.birthDate, displayedComponents: .date)
                    HStack {
                        Text("身高 (cm)")
                        Spacer()
                        TextField("身高", value: $viewModel.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("heightField")
                    }
                    HStack {
                        Text("当前体重 (kg)")
                        Spacer()
                        TextField("体重", value: $viewModel.initialWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("weightField")
                    }
                    Picker("活动水平", selection: $viewModel.activityFactor) {
                        Text("久坐").tag(1.2)
                        Text("轻度活动").tag(1.375)
                        Text("中度活动").tag(1.55)
                        Text("高强度").tag(1.725)
                    }
                }
                Section("减脂目标") {
                    HStack {
                        Text("目标体重 (kg)")
                        Spacer()
                        TextField("目标体重", value: $viewModel.targetWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("targetWeightField")
                    }
                    LabeledContent("每日热量目标", value: "\(Int(viewModel.defaultTargets.kcal)) kcal")
                    LabeledContent("蛋白质 / 脂肪 / 碳水", value: "\(Int(viewModel.defaultTargets.protein))g / \(Int(viewModel.defaultTargets.fat))g / \(Int(viewModel.defaultTargets.carb))g")
                    LabeledContent("每日饮水目标", value: "\(Int(viewModel.defaultWaterMl)) ml")
                    Text("减脂速率不手动设定，由体重与能量趋势动态计算（spec 5.3）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("欢迎使用轻卡")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        try? viewModel.save(into: store)
                        dismiss()
                    }
                    .accessibilityIdentifier("finishOnboarding")
                }
            }
        }
    }
}
```

- [ ] **Step 6: 改 LightCalApp.swift（无档案 → Onboarding；有档案 → 占位主页，Task 16 替换）**

```swift
import SwiftUI
import SwiftData

@main
struct LightCalApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    private let container = AppContainer.shared

    var body: some View {
        if (try? container.store.profile()) != nil {
            Text("主页占位（Task 16 替换为 RootTabView）")
                .font(.title)
                .foregroundStyle(DesignTokens.primary)
        } else {
            OnboardingView(store: container.store)
        }
    }
}
```

- [ ] **Step 7: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: 手工构建冒烟**

Run: `xcodebuild build -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `** BUILD SUCCEEDED **`（若 AppContainer 并发隔离报错，按 Task 15 Step 3 注意事项调整）

- [ ] **Step 9: Commit**

```bash
git add LightCal/App LightCal/UI/Onboarding LightCalTests/OnboardingViewModelTests.swift
git commit -m "feat: 依赖装配与首次建档向导"
```

---

### Task 16: 今日仪表盘 + 确认卡片 + 保存流程（含饮水快加）

**Files:**
- Create: `LightCal/UI/Formatting.swift`
- Create: `LightCal/UI/Today/TodayViewModel.swift`
- Create: `LightCal/UI/Today/TodayDashboardView.swift`
- Create: `LightCal/UI/Logging/ConfirmCardView.swift`
- Create: `LightCal/UI/RootTabView.swift`
- Modify: `LightCal/App/LightCalApp.swift`（AppRootView 改用 RootTabView）
- Test: `LightCalTests/TodayViewModelTests.swift`、`LightCalTests/FormattingTests.swift`
- UI Test: `LightCalUITests/TodayFlowUITests.swift`

**Interfaces:**
- Consumes: AppContainer（Task 15）全量
- Produces:
  - `enum Formatting { static func kcalText(_ v: Double) -> String; static func gramsText(_ v: Double) -> String; static func daysText(_ v: Double?) -> String; static func mlText(_ v: Double) -> String }`
  - `@MainActor @Observable final class TodayViewModel`：`var selectedMeal: MealKind`、`var draft: LogDraft?`；`func refresh(store:pipeline:healthKit:goal:) async`；`var summary: DaySummary`、`var gap: GapAnalysis`、`var suggestions: [FoodSuggestion]`、`var prediction: PredictionScenarios?`、`var waterText: String`、`func addWater(ml:) `、`func saveDraft(into:)`
  - `struct TodayDashboardView: View`（accessibilityIdentifier：`addEntry`、`waterQuick250`、`waterQuick500`、`saveDraft`）
  - `struct ConfirmCardView: View`（可编辑条目列表 + 餐次选择 + 保存）
  - `struct RootTabView: View`（TabView：今日/趋势占位/我的占位 + 浮动 + 按钮）
  - Task 17/18/19 依赖。

- [ ] **Step 1: 写失败测试（Formatting + TodayViewModel）**

```swift
import XCTest
@testable import LightCal

final class FormattingTests: XCTestCase {
    func testKcalText() {
        XCTAssertEqual(Formatting.kcalText(1800), "1800")
        XCTAssertEqual(Formatting.kcalText(1800.5), "1801")
        XCTAssertEqual(Formatting.kcalText(-320), "-320")
    }

    func testGramsText() {
        XCTAssertEqual(Formatting.gramsText(28.4), "28g")
    }

    func testDaysText() {
        XCTAssertEqual(Formatting.daysText(49), "49 天")
        XCTAssertEqual(Formatting.daysText(nil), "--")
    }

    func testMlText() {
        XCTAssertEqual(Formatting.mlText(2100), "2100")
    }
}

@MainActor
final class TodayViewModelTests: XCTestCase {
    private func makeViewModel() async throws -> TodayViewModel {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))
        let database = FoodDatabase(foods: [FoodRecord(name: "鸡胸肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), defaultServingGrams: 100)])
        let vm = TodayViewModel(store: store, database: database, healthKit: MockHealthKit(), pipeline: MockPipeline())
        await vm.refresh()
        return vm
    }

    func testGapAfterSavingChicken() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()
        XCTAssertEqual(vm.summary.totalNutrition.kcal, 133, accuracy: 0.001)
        XCTAssertEqual(vm.gap.remainingKcal, 1800 - 133, accuracy: 0.001)
        XCTAssertEqual(vm.gap.proteinGap, 126 - 24.6, accuracy: 0.001)
    }

    func testWaterQuickAdd() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 500)
        await vm.refresh()
        XCTAssertEqual(vm.summary.waterMl, 500)
        XCTAssertEqual(vm.waterText, "500 / 2100 ml")
    }

    func testSuggestionsAppearWhenProteinGap() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "米饭", grams: 300, nutrition: NutritionFacts(kcal: 348, protein: 7.8, fat: 0.9, carb: 77.7), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()
        XCTAssertFalse(vm.suggestions.isEmpty)
        XCTAssertEqual(vm.suggestions.first?.name, "鸡胸肉")
    }
}
```

> `MockPipeline`：本任务测试文件底部直接定义（不依赖 Task 13 测试文件）：

```swift
final class MockPipeline: LoggingPipelining, @unchecked Sendable {
    func process(text: String) async throws -> LogDraft { LogDraft(items: [], originalText: text) }
    func process(photoData: Data) async throws -> LogDraft { LogDraft(items: [], originalText: nil) }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FormattingTests -only-testing:LightCalTests/TodayViewModelTests`
Expected: FAIL，`cannot find 'Formatting' in scope`

- [ ] **Step 3: 写 Formatting.swift**

```swift
import Foundation

enum Formatting {
    static func kcalText(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func gramsText(_ value: Double) -> String {
        "\(Int(value.rounded()))g"
    }

    static func daysText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded())) 天"
    }

    static func mlText(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
```

- [ ] **Step 4: 写 TodayViewModel.swift**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private let store: DataStore
    private let database: FoodDatabase
    private let healthKit: HealthKitServing
    private let pipeline: LoggingPipelining

    var selectedMeal: MealKind = .lunch
    var draft: LogDraft?
    private(set) var summary = DaySummary(totalNutrition: NutritionFacts(), waterMl: 0)
    private(set) var gap = GapAnalysis(remainingKcal: 0, proteinGap: 0, carbGap: 0, fatGap: 0)
    private(set) var suggestions: [FoodSuggestion] = []
    private(set) var prediction: PredictionScenarios?
    private(set) var weightRate: Double?
    private(set) var energyRate: Double?

    init(store: DataStore, database: FoodDatabase, healthKit: HealthKitServing, pipeline: LoggingPipelining) {
        self.store = store
        self.database = database
        self.healthKit = healthKit
        self.pipeline = pipeline
    }

    var waterTargetMl: Double {
        (try? store.currentGoal()?.waterTargetMl) ?? 2100
    }

    var waterText: String {
        "\(Formatting.mlText(summary.waterMl)) / \(Formatting.mlText(waterTargetMl)) ml"
    }

    func refresh() async {
        let now = Date()
        summary = (try? store.daySummary(now)) ?? DaySummary(totalNutrition: NutritionFacts(), waterMl: 0)
        let goal = try? store.currentGoal()
        let targets = goal?.targets ?? DailyTargets()

        let intake = summary.totalNutrition
        gap = GapAnalysis(
            remainingKcal: targets.kcal - intake.kcal,
            proteinGap: targets.protein - intake.protein,
            carbGap: targets.carb - intake.carb,
            fatGap: targets.fat - intake.fat
        )

        // 建议清单：候选池 = 内置库 + 自定义食物（AI 估算不进池，spec 6.2）
        var candidates = database.foods
        if let custom = try? store.allCustomFoods() {
            candidates += custom.map {
                FoodRecord(name: $0.name, aliases: [], nutritionPer100g: $0.nutritionPer100g, defaultServingGrams: 100)
            }
        }
        let eaten = Set((try? store.logItems(on: now).map(\.name)) ?? [])
        suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: eaten)

        // 预测（spec 5.3/5.4）
        let samples = (try? store.weightSamples(limit: 50)) ?? []
        let localWeightRate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples)
        var deficits: [Double] = []   // deficit[i] = 消耗[i] - 摄入[i]（正 = 有缺口）
        var totalIntake = 0.0
        let calendar = Calendar.current
        var deficitDays = 0
        for daysAgo in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let intake = (try? store.daySummary(day))?.totalNutrition.kcal ?? 0
            let bmr = Self.bmrForCurrentProfile(store: store)
            let active = (try? await healthKit.activeEnergyKcal(on: day)) ?? 0
            deficits.append(bmr + active - intake)
            totalIntake += intake
            deficitDays += 1
        }
        let energyRate = RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: deficits)
        weightRate = localWeightRate
        self.energyRate = energyRate

        let latestWeight = samples.first?.weightKg ?? (try? store.profile())?.initialWeightKg ?? 0
        let targetWeight = goal?.targetWeightKg ?? 0
        // 平均总消耗 = 平均摄入 + 平均缺口（deficit = 消耗 - 摄入 恒等变形）
        let avgDeficit = deficitDays > 0 ? deficits.reduce(0, +) / Double(deficitDays) : 0
        let avgIntake = deficitDays > 0 ? totalIntake / Double(deficitDays) : 0
        let avgExpenditure = avgIntake + avgDeficit

        prediction = PredictionCalculator.scenarios(
            currentWeightKg: latestWeight,
            targetWeightKg: targetWeight,
            weightRate: localWeightRate,
            energyRate: energyRate,
            targetKcal: targets.kcal,
            avgDailyExpenditureLast7d: avgExpenditure
        )
    }

    private static func bmrForCurrentProfile(store: DataStore) -> Double {
        guard let profile = try? store.profile() else { return 1600 }
        let age = Calendar.current.dateComponents([.year], from: profile.birthDate, to: .now).year ?? 30
        let input = ProfileInput(
            sex: Sex(rawValue: profile.sex) ?? .male,
            ageYears: age,
            heightCm: profile.heightCm,
            weightKg: profile.initialWeightKg,
            activityFactor: profile.activityFactor
        )
        return NutritionCalculator.bmr(input)
    }

    func addWater(ml: Double) {
        try? store.addWater(ml: ml, date: .now)
    }

    func saveDraft(items: [CompletedFoodItem]? = nil) {
        let toSave = items ?? draft?.items ?? []
        guard !toSave.isEmpty else { return }
        try? store.saveLogItems(toSave, date: .now, meal: selectedMeal)
        self.draft = nil
    }
}
```

> 注：`refresh()` 的预测部分已在上方代码中完整实现——近 7 天逐日算「缺口 = BMR + HealthKit 主动消耗 − 摄入」，能量速率 = 平均缺口 ÷ 7700 × 7；三情景传入的 `avgDailyExpenditureLast7d = 平均摄入 + 平均缺口`（由 deficit = 消耗 − 摄入 恒等变形得到）。

- [ ] **Step 5: 写 TodayDashboardView.swift + ConfirmCardView.swift + RootTabView.swift**

```swift
import SwiftUI

struct TodayDashboardView: View {
    @State private var viewModel: TodayViewModel
    @State private var showingEntry = false
    @State private var showingConfirm = false

    init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    calorieCard
                    waterCard
                    suggestionCard
                    predictionCard
                    timelineCard
                }
                .padding()
            }
            .background(DesignTokens.background)
            .navigationTitle("今日")
            .task { await viewModel.refresh() }
            .sheet(isPresented: $showingEntry) {
                EntryPointSheet { draft in
                    viewModel.draft = draft
                    showingConfirm = true
                }
            }
            .sheet(isPresented: $showingConfirm) {
                if let draft = viewModel.draft {
                    ConfirmCardView(
                        draft: draft,
                        meal: $viewModel.selectedMeal,
                        onSave: { items in
                            viewModel.saveDraft(items: items)
                            showingConfirm = false
                            Task { await viewModel.refresh() }
                        }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .accessibilityLabel("添加食物")
                    }
                    .accessibilityIdentifier("addEntry")
                }
            }
        }
    }

    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("剩余热量")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Formatting.kcalText(viewModel.gap.remainingKcal)) kcal")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(viewModel.gap.remainingKcal >= 0 ? DesignTokens.accent : DesignTokens.destructive)
            MacroProgressBar(label: "蛋白质", current: viewModel.summary.totalNutrition.protein, target: viewModel.gap.proteinGap + viewModel.summary.totalNutrition.protein, color: DesignTokens.primary)
            MacroProgressBar(label: "脂肪", current: viewModel.summary.totalNutrition.fat, target: viewModel.gap.fatGap + viewModel.summary.totalNutrition.fat, color: DesignTokens.accent)
            MacroProgressBar(label: "碳水", current: viewModel.summary.totalNutrition.carb, target: viewModel.gap.carbGap + viewModel.summary.totalNutrition.carb, color: Color(hex: 0x7C3AED))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("饮水").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(viewModel.summary.waterMl / max(viewModel.waterTargetMl, 1), 1))
                .tint(DesignTokens.primary)
            Text(viewModel.waterText).font(.headline).monospacedDigit()
            HStack(spacing: DesignTokens.touchGap) {
                Button("+250ml") { viewModel.addWater(ml: 250); Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignTokens.minTouchSize)
                    .accessibilityIdentifier("waterQuick250")
                Button("+500ml") { viewModel.addWater(ml: 500); Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignTokens.minTouchSize)
                    .accessibilityIdentifier("waterQuick500")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var suggestionCard: some View {
        Group {
            if !viewModel.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("缺口建议").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(viewModel.suggestions, id: \.name) { suggestion in
                        Text("\(suggestion.name) \(Formatting.gramsText(suggestion.grams)) · \(Formatting.kcalText(suggestion.nutrition.kcal)) kcal")
                            .font(.callout)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var predictionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("达标预测").font(.subheadline).foregroundStyle(.secondary)
            if let prediction = viewModel.prediction, let trend = prediction.trendDays {
                Text("按当前趋势预计 \(Formatting.daysText(trend)) 达标")
                    .font(.headline)
                Text("保守 \(Formatting.daysText(prediction.conservativeDays)) · 按目标缺口 \(Formatting.daysText(prediction.targetDays))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.weightRate == nil {
                Text("多记录几天体重后给出预测").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("趋势计算中…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日记录").font(.subheadline).foregroundStyle(.secondary)
            let items = (try? AppContainer.shared.store.logItems(on: .now)) ?? []
            if items.isEmpty {
                Text("还没有记录，点右上角 + 开始打卡").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.persistentModelID) { item in
                    HStack {
                        Text(item.meal)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.primary.opacity(0.15))
                            .clipShape(Capsule())
                        Text("\(item.name) \(Formatting.gramsText(item.grams))")
                            .font(.callout)
                        if item.source == NutritionSource.aiEstimated.rawValue {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.aiAmber)
                                .accessibilityLabel("AI 估算")
                        }
                        Spacer()
                        Text("\(Formatting.kcalText(item.nutrition.kcal)) kcal")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MacroProgressBar: View {
    let label: String
    let current: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Formatting.gramsText(current)) / \(Formatting.gramsText(target))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(current / max(target, 1), 1))
                .tint(current > target ? DesignTokens.destructive : color)
        }
    }
}
```

```swift
import SwiftUI

struct ConfirmCardView: View {
    let draft: LogDraft
    @Binding var meal: MealKind
    let onSave: ([CompletedFoodItem]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var grams: [Double]   // 与 draft.items 平行的可编辑份量

    init(draft: LogDraft, meal: Binding<MealKind>, onSave: @escaping ([CompletedFoodItem]) -> Void) {
        self.draft = draft
        self._meal = meal
        self.onSave = onSave
        self._grams = State(initialValue: draft.items.map(\.grams))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("餐次") {
                    Picker("餐次", selection: $meal) {
                        ForEach(MealKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("确认食物（可修改份量）") {
                    ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text(item.name)
                            if item.source == .aiEstimated {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.aiAmber)
                                    .accessibilityLabel("AI 估算")
                            }
                            Spacer()
                            TextField("克", value: $grams[index], format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("\(Formatting.kcalText(item.nutrition.kcal)) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier("confirmItem\(index)")
                    }
                    if draft.items.isEmpty, let text = draft.originalText {
                        Text("未能解析「\(text)」，请手动添加食物")
                            .font(.callout)
                            .foregroundStyle(DesignTokens.destructive)
                    }
                }
            }
            .navigationTitle("确认记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Self.rescaledItems(draft.items, grams: grams))
                    }
                    .disabled(draft.items.isEmpty)
                    .accessibilityIdentifier("saveDraft")
                }
            }
        }
    }

    /// 份量修改后按比例重算营养快照（spec 4.4 可编辑）
    static func rescaledItems(_ items: [CompletedFoodItem], grams: [Double]) -> [CompletedFoodItem] {
        zip(items, grams).map { item, newGrams in
            let factor = item.grams > 0 ? newGrams / item.grams : 1
            var nutrition = item.nutrition
            nutrition.kcal *= factor
            nutrition.protein *= factor
            nutrition.fat *= factor
            nutrition.carb *= factor
            nutrition.extras = nutrition.extras.mapValues { $0 * factor }
            return CompletedFoodItem(name: item.name, grams: newGrams, nutrition: nutrition, source: item.source)
        }
    }
}
```

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayDashboardView(viewModel: TodayViewModel(
                store: AppContainer.shared.store,
                database: AppContainer.shared.database,
                healthKit: AppContainer.shared.healthKit,
                pipeline: AppContainer.shared.pipeline
            ))
            .tabItem { Label("今日", systemImage: "sun.max.fill") }

            Text("趋势页（Task 18）")
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }

            Text("我的页（Task 19）")
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
```

- [ ] **Step 6: 改 LightCalApp.swift**

```swift
import SwiftUI
import SwiftData

@main
struct LightCalApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    private let container = AppContainer.shared

    var body: some View {
        if (try? container.store.profile()) != nil {
            RootTabView()
        } else {
            OnboardingView(store: container.store)
        }
    }
}
```

- [ ] **Step 7: 写 UI 冒烟测试**

```swift
import XCTest

final class TodayFlowUITests: XCTestCase {
    @MainActor
    func testWaterQuickAddAndTextLogging() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]   // 内存库 + 种子档案（跳过 Onboarding）
        app.launch()

        // 饮水快加
        let water = app.buttons["waterQuick500"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.tap()
        XCTAssertTrue(app.staticTexts["500 / 2100 ml"].waitForExistence(timeout: 5))

        // 文字录入：无 API Key 时走本地正则兜底
        app.buttons["addEntry"].tap()
        app.buttons["textEntry"].tap()
        let field = app.textFields["logTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("100g鸡胸肉")
        app.buttons["parseAndConfirm"].tap()
        XCTAssertTrue(app.staticTexts["鸡胸肉"].waitForExistence(timeout: 10))
        app.buttons["saveDraft"].tap()

        // 时间线出现记录
        XCTAssertTrue(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["133 kcal"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 8: 运行确认通过（单元 + UI）**

Run:
```bash
xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FormattingTests -only-testing:LightCalTests/TodayViewModelTests -only-testing:LightCalUITests/TodayFlowUITests
```
Expected: `** TEST SUCCEEDED **`
> 注意：UI 测试依赖 Task 17 的 `EntryPointSheet`（`textEntry`/`logTextField`/`parseAndConfirm` 标识符），若 Task 17 尚未实现则 UI 测试先行跳过（`-skip-testing:LightCalUITests`），在 Task 17 完成后补跑。**Task 16 的 commit 要求单元测试通过即可。**

- [ ] **Step 9: Commit**

```bash
git add LightCal/UI LightCal/App/LightCalApp.swift LightCalTests LightCalUITests
git commit -m "feat: 今日仪表盘+确认卡片+保存流程（含饮水快加）"
```

---

### Task 17: 录入入口（拍照/语音/文字）

**Files:**
- Create: `LightCal/UI/Logging/EntryPointSheet.swift`
- Create: `LightCal/UI/Logging/CameraPicker.swift`
- Test: `LightCalUITests/TodayFlowUITests.swift`（补跑 Task 16 的 UI 测试）

**Interfaces:**
- Consumes: AppContainer（Task 15）、ConfirmCardView（Task 16）
- Produces: `struct EntryPointSheet: View`（三个入口按钮：拍照/语音/文字；完成解析后回调 `(LogDraft) -> Void`；accessibilityIdentifier：`textEntry`、`photoEntry`、`voiceEntry`、`logTextField`、`parseAndConfirm`）
- 拍照：`CameraPicker`（UIImagePickerController 相机）→ JPEG Data → `pipeline.process(photoData:)`；识别失败弹提示并切到文字输入
- 语音：`speechTranscriber.transcribeLive()` → 文本 → `pipeline.process(text:)`；失败提示改用打字
- Task 18/19 不依赖本任务。

- [ ] **Step 1: 写实现 EntryPointSheet.swift**

```swift
import SwiftUI
import PhotosUI

struct EntryPointSheet: View {
    var onDraft: (LogDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: EntryMode? = nil
    @State private var text = ""
    @State private var isParsing = false
    @State private var errorMessage: String?

    enum EntryMode { case photo, voice, text }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if mode == nil {
                    entryButtons
                } else if mode == .text {
                    textEntry
                } else if mode == .voice {
                    voiceEntry
                }
            }
            .padding()
            .navigationTitle("添加食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var entryButtons: some View {
        VStack(spacing: DesignTokens.touchGap) {
            Button {
                showingCamera = true
            } label: {
                Label("拍照识别", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("photoEntry")

            Button {
                mode = .voice
            } label: {
                Label("语音输入", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("voiceEntry")

            Button {
                mode = .text
            } label: {
                Label("文字输入", systemImage: "keyboard")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("textEntry")
        }
    }

    private var textEntry: some View {
        VStack(spacing: 12) {
            TextField("例如：一碗米饭 100g鸡胸肉", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier("logTextField")
            if isParsing {
                ProgressView("解析中…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.destructive)
            }
            Button("解析并确认") {
                Task { await parseText() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accent)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
            .frame(minHeight: DesignTokens.minTouchSize)
            .accessibilityIdentifier("parseAndConfirm")
            Spacer()
        }
    }

    private var voiceEntry: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.primary)
            Text("点击开始说话，说完自动转写")
                .font(.callout)
                .foregroundStyle(.secondary)
            if isParsing {
                ProgressView("正在聆听…")
            }
            Button("开始说话") {
                Task { await transcribe() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .disabled(isParsing)
            .frame(minHeight: DesignTokens.minTouchSize)
            .accessibilityIdentifier("voiceStart")
            Spacer()
        }
    }

    private func parseText() async {
        isParsing = true
        errorMessage = nil
        do {
            let draft = try await AppContainer.shared.pipeline.process(text: text)
            finish(with: draft)
        } catch {
            errorMessage = "解析失败：\(error.localizedDescription)"
        }
        isParsing = false
    }

    private func transcribe() async {
        isParsing = true
        errorMessage = nil
        do {
            let transcript = try await AppContainer.shared.speechTranscriber.transcribeLive()
            let draft = try await AppContainer.shared.pipeline.process(text: transcript)
            finish(with: draft)
        } catch {
            errorMessage = "语音识别失败，请改用文字输入"
        }
        isParsing = false
    }

    private func handlePhotoData(_ data: Data) {
        Task {
            isParsing = true
            do {
                let draft = try await AppContainer.shared.pipeline.process(photoData: data)
                finish(with: draft)
            } catch {
                errorMessage = "未能识别出食物，请改用文字输入"
                mode = .text
            }
            isParsing = false
        }
    }

    private func finish(with draft: LogDraft) {
        dismiss()
        onDraft(draft)
    }
}
```

- [ ] **Step 2: 写 CameraPicker.swift（UIImagePickerController 相机，照片数据即用即弃）**

```swift
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onImageData(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

- [ ] **Step 3: EntryPointSheet 挂上相机 fullScreenCover（Step 1 的 photoEntry 已直接触发）**

在 `EntryPointSheet` 增加状态 `@State private var showingCamera = false`，并在 body 的 VStack 上挂：

```swift
.fullScreenCover(isPresented: $showingCamera) {
    CameraPicker { data in
        handlePhotoData(data)
    }
    .ignoresSafeArea()
}
```

- [ ] **Step 4: 补跑 Task 16 的 UI 测试（验证文字路径端到端）**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalUITests/TodayFlowUITests`
Expected: `** TEST SUCCEEDED **`（文字路径走本地正则兜底，无需 API Key；照片/语音路径真机手工验证）

- [ ] **Step 5: 真机手工验证清单（不阻塞 commit）**

相机：拍鸡胸肉+米饭照片 → Vision 识别 → 确认卡片；语音：说「一碗米饭两个鸡蛋」→ 转写解析 → 确认卡片；无网环境：文字录入仍可用（本地兜底）。

- [ ] **Step 6: Commit**

```bash
git add LightCal/UI/Logging LightCalUITests
git commit -m "feat: 录入入口（拍照/语音/文字）"
```

---

### Task 18: 趋势页（Swift Charts）

**Files:**
- Create: `LightCal/UI/Trends/TrendsViewModel.swift`
- Create: `LightCal/UI/Trends/TrendsView.swift`
- Modify: `LightCal/UI/RootTabView.swift`（趋势 Tab 换成 TrendsView）
- Test: `LightCalTests/TrendsViewModelTests.swift`

**Interfaces:**
- Consumes: DataStore（Task 9）、LinearRegression（Task 10）、DesignTokens（Task 1）
- Produces:
  - `struct WeightPoint: Identifiable, Equatable { id: UUID, date: Date, kg: Double }`
  - `struct IntakePoint: Identifiable, Equatable { id: UUID, date: Date, kcal: Double }`
  - `@MainActor @Observable final class TrendsViewModel`：`var range: Range`（周/月/3月/全部）、`private(set) var weightPoints/trenndPoints/intakePoints/targetKcal/hasEnoughWeightData`、`init(store:)`、`func refresh() async`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

@MainActor
final class TrendsViewModelTests: XCTestCase {
    private func makeSeededStore() throws -> DataStore {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))
        // 4 个体重点：体重趋势可用，图表达标（spec 7.6 ≥4 点才画图）
        for (daysAgo, kg) in [(30, 70.0), (20, 69.6), (10, 69.2), (0, 68.9)] {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            try store.addWeight(kg: kg, date: date)
        }
        // 昨天的打卡
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        try store.saveLogItems([CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133), source: .builtin)], date: yesterday, meal: .lunch)
        return store
    }

    func testMonthRangeYields4WeightPointsAndEnoughIntake() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .month
        await vm.refresh()
        XCTAssertEqual(vm.weightPoints.count, 4)
        XCTAssertTrue(vm.hasEnoughWeightData)
        XCTAssertEqual(vm.targetKcal, 1800)
        XCTAssertGreaterThanOrEqual(vm.intakePoints.count, 30)  // 月视图：近 30 天逐日
    }

    func testWeekRangeYields7IntakePoints() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .week
        await vm.refresh()
        XCTAssertEqual(vm.intakePoints.count, 7)
        XCTAssertEqual(vm.weightPoints.count, 1)  // 只有 0 天前的体重在 7 天窗口内
    }

    func testTrendLineFitsFallingWeights() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .month
        await vm.refresh()
        XCTAssertEqual(vm.trendPoints.count, 2)
        // 趋势线两端：起端 ≈ 拟合截距、末端低于起端（体重在降）
        XCTAssertGreaterThan(vm.trendPoints[0].kg, vm.trendPoints[1].kg)
    }

    func testInsufficientWeightDataShowsStatCardNotChart() async throws {
        let store = try DataStore.makeInMemory()
        try store.addWeight(kg: 70, date: .now)
        let vm = TrendsViewModel(store: store)
        vm.range = .week
        await vm.refresh()
        XCTAssertFalse(vm.hasEnoughWeightData)
        XCTAssertTrue(vm.trendPoints.isEmpty)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/TrendsViewModelTests`
Expected: FAIL，`cannot find 'TrendsViewModel' in scope`

- [ ] **Step 3: 写 TrendsViewModel.swift**

```swift
import Foundation
import Observation

struct WeightPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let kg: Double
}

struct IntakePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let kcal: Double
}

@MainActor
@Observable
final class TrendsViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week = "周", month = "月", quarter = "3月", all = "全部"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    var range: Range = .month
    private(set) var weightPoints: [WeightPoint] = []
    private(set) var trendPoints: [WeightPoint] = []
    private(set) var intakePoints: [IntakePoint] = []
    private(set) var targetKcal: Double = 0
    private(set) var hasEnoughWeightData = false

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    func refresh() async {
        let calendar = Calendar.current
        let now = Date()
        let cutoff = range.days.map { calendar.date(byAdding: .day, value: -$0, to: now)! }

        let samples = ((try? store.weightSamples(limit: 400)) ?? [])
            .filter { cutoff.map { $0.date >= $0 } ?? true }
            .sorted { $0.date < $1.date }
        weightPoints = samples.map { WeightPoint(date: $0.date, kg: $0.weightKg) }
        hasEnoughWeightData = samples.count >= 4   // spec 7.6：数据点 < 4 显示统计卡

        if samples.count >= 3, let firstDate = samples.first?.date {
            let points = samples.map { (x: $0.date.timeIntervalSince(firstDate) / 86400, y: $0.weightKg) }
            if let fit = LinearRegression.fit(points: points) {
                trendPoints = [
                    WeightPoint(date: firstDate, kg: fit.intercept + fit.slope * points.first!.x),
                    WeightPoint(date: samples.last!.date, kg: fit.intercept + fit.slope * points.last!.x)
                ]
            }
        } else {
            trendPoints = []
        }

        var intake: [IntakePoint] = []
        let start = cutoff.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: samples.first?.date ?? now)
        var day = start
        let end = calendar.startOfDay(for: now)
        while day <= end {
            intake.append(IntakePoint(date: day, kcal: (try? store.daySummary(day))?.totalNutrition.kcal ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        intakePoints = intake
        targetKcal = (try? store.currentGoal())?.targets.kcal ?? 0
    }
}
```

- [ ] **Step 4: 写 TrendsView.swift（spec 7.3/7.6：线型区分系列、柱上目标线）**

```swift
import SwiftUI
import Charts

struct TrendsView: View {
    @State private var viewModel: TrendsViewModel

    init(viewModel: TrendsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $viewModel.range) {
                        ForEach(TrendsViewModel.Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.range) {
                        Task { await viewModel.refresh() }
                    }
                    weightCard
                    intakeCard
                }
                .padding()
            }
            .background(DesignTokens.background)
            .navigationTitle("趋势")
            .task { await viewModel.refresh() }
        }
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("体重").font(.subheadline).foregroundStyle(.secondary)
            if viewModel.hasEnoughWeightData {
                Chart {
                    ForEach(viewModel.trendPoints) { point in
                        LineMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.targetLine)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                    ForEach(viewModel.weightPoints) { point in
                        LineMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.primary)
                        PointMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.primary)
                    }
                }
                .frame(height: 180)
            } else {
                Text("体重数据不足 4 个点，多记录几天后展示趋势图")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日摄入 vs 目标").font(.subheadline).foregroundStyle(.secondary)
            Chart(viewModel.intakePoints) { point in
                BarMark(x: .value("日期", point.date, unit: .day), y: .value("摄入", point.kcal))
                    .foregroundStyle(DesignTokens.primary.opacity(0.7))
                RuleMark(y: .value("目标", viewModel.targetKcal))
                    .foregroundStyle(DesignTokens.targetLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 180)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

- [ ] **Step 5: RootTabView 趋势 Tab 换成 TrendsView**

```swift
TrendsView(viewModel: TrendsViewModel(store: AppContainer.shared.store))
    .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
```

- [ ] **Step 6: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add LightCal/UI/Trends LightCal/UI/RootTabView.swift LightCalTests/TrendsViewModelTests.swift
git commit -m "feat: 趋势页（体重折线+摄入柱状+目标线）"
```

---

### Task 19: 我的页（目标/自定义食物/设置/体重/导出）

**Files:**
- Create: `LightCal/UI/Profile/ProfileView.swift`
- Create: `LightCal/UI/Profile/EditGoalSheet.swift`
- Create: `LightCal/UI/Profile/CustomFoodsView.swift`
- Modify: `LightCal/UI/Logging/ConfirmCardView.swift`（AI 估算条目加「存为我的食物」）
- Modify: `LightCal/UI/Formatting.swift`（增加 weightText）
- Modify: `LightCal/UI/RootTabView.swift`（我的 Tab 换成 ProfileView）
- Test: `LightCalTests/FormattingTests.swift`（补 weightText 用例）、`LightCalTests/ProfileFlowTests.swift`

**Interfaces:**
- Consumes: DataStore（Task 9）、HealthKitServing（Task 12）、AppContainer（Task 15）
- Produces:
  - `struct ProfileView: View`（目标卡/修改目标/体重录入/自定义食物/设置/导出，含隐私信号文案）
  - `struct EditGoalSheet: View`（改目标体重与四项营养/饮水 → appendGoal 新版本留档）
  - `struct CustomFoodsView: View`（增删改）
  - `enum WeightUnit: String, CaseIterable { case kg, jin }`；`Formatting.weightText(kg:unit:)`
  - `enum SettingsKeys { static let deepseekApiKey/writeBackToHealthKit/weightUnit }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LightCal

final class FormattingWeightTests: XCTestCase {
    func testWeightTextKg() {
        XCTAssertEqual(Formatting.weightText(kg: 70, unit: .kg), "70.0 kg")
    }

    func testWeightTextJin() {
        XCTAssertEqual(Formatting.weightText(kg: 70, unit: .jin), "140.0 斤")
    }
}

@MainActor
final class ProfileFlowTests: XCTestCase {
    func testEditGoalAppendsNewVersionKeepingHistory() throws {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))

        // 模拟 EditGoalSheet 的保存逻辑
        let newTargets = DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195)
        try store.appendGoal(Goal(
            targetWeightKg: 64, startDate: .now, startWeightKg: 69,
            targets: newTargets, systemTargets: targets, waterTargetMl: 2070
        ))
        XCTAssertEqual(try store.allGoals().count, 2)
        XCTAssertEqual(try store.currentGoal()?.targetWeightKg, 64)
        // 系统默认值保留旧版，微调值为新版（spec 3.2）
        XCTAssertEqual(try store.currentGoal()?.systemTargets, targets)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FormattingWeightTests -only-testing:LightCalTests/ProfileFlowTests`
Expected: FAIL，`cannot find 'weightText' in scope`

- [ ] **Step 3: Formatting.swift 增加体重文本**

```swift
enum WeightUnit: String, CaseIterable {
    case kg, jin
}

// Formatting 内追加：
static func weightText(kg: Double, unit: WeightUnit) -> String {
    switch unit {
    case .kg: "\(String(format: "%.1f", kg)) kg"
    case .jin: "\(String(format: "%.1f", kg * 2)) 斤"
    }
}
```

- [ ] **Step 4: 写 EditGoalSheet.swift**

```swift
import SwiftUI

struct EditGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DataStore
    let current: Goal?

    @State private var targetWeightKg: Double = 65
    @State private var kcal: Double = 1800
    @State private var protein: Double = 126
    @State private var fat: Double = 56
    @State private var carb: Double = 200
    @State private var waterMl: Double = 2100

    var body: some View {
        NavigationStack {
            Form {
                Section("目标（修改后生成新版本，历史留档）") {
                    LabeledContent("目标体重 (kg)") {
                        TextField("目标体重", value: $targetWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("每日营养目标") {
                    LabeledContent("热量 (kcal)") { numberField("kcal", $kcal) }
                    LabeledContent("蛋白质 (g)") { numberField("protein", $protein) }
                    LabeledContent("脂肪 (g)") { numberField("fat", $fat) }
                    LabeledContent("碳水 (g)") { numberField("carb", $carb) }
                    LabeledContent("饮水 (ml)") { numberField("water", $waterMl) }
                }
            }
            .navigationTitle("修改目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let system = current?.systemTargets ?? DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb)
                        try? store.appendGoal(Goal(
                            targetWeightKg: targetWeightKg,
                            startDate: .now,
                            startWeightKg: (try? store.weightSamples(limit: 1).first?.weightKg) ?? current?.startWeightKg ?? targetWeightKg,
                            targets: DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb),
                            systemTargets: system,
                            waterTargetMl: waterMl
                        ))
                        dismiss()
                    }
                    .accessibilityIdentifier("saveGoal")
                }
            }
            .onAppear {
                if let current {
                    targetWeightKg = current.targetWeightKg
                    kcal = current.targets.kcal
                    protein = current.targets.protein
                    fat = current.targets.fat
                    carb = current.targets.carb
                    waterMl = current.waterTargetMl
                }
            }
        }
    }

    private func numberField(_ id: String, _ value: Binding<Double>) -> some View {
        TextField(id, value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            .accessibilityIdentifier(id)
    }
}
```

- [ ] **Step 5: 写 CustomFoodsView.swift**

```swift
import SwiftUI

struct CustomFoodsView: View {
    let store: DataStore
    @State private var foods: [CustomFood] = []
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(foods, id: \.persistentModelID) { food in
                VStack(alignment: .leading) {
                    Text(food.name).font(.headline)
                    Text("每100g：\(Formatting.kcalText(food.nutritionPer100g.kcal)) kcal · 蛋白 \(Formatting.gramsText(food.nutritionPer100g.protein)) · 脂肪 \(Formatting.gramsText(food.nutritionPer100g.fat)) · 碳水 \(Formatting.gramsText(food.nutritionPer100g.carb))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    try? store.deleteCustomFood(foods[index])
                }
                reload()
            }
        }
        .navigationTitle("自定义食物")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addCustomFood")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCustomFoodSheet(store: store) { reload() }
        }
        .onAppear { reload() }
    }

    private func reload() {
        foods = (try? store.allCustomFoods()) ?? []
    }
}

struct AddCustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DataStore
    let onSaved: () -> Void

    @State private var name = ""
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var carb: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("食物名", text: $name)
                LabeledContent("热量 (kcal/100g)") { TextField("kcal", value: $kcal, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("蛋白质 (g/100g)") { TextField("protein", value: $protein, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("脂肪 (g/100g)") { TextField("fat", value: $fat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("碳水 (g/100g)") { TextField("carb", value: $carb, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("添加自定义食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        try? store.saveCustomFood(CustomFood(name: name, nutritionPer100g: NutritionFacts(kcal: kcal, protein: protein, fat: fat, carb: carb)))
                        onSaved()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
```

- [ ] **Step 6: ConfirmCardView 给 AI 估算条目加「存为我的食物」**

在 Task 16 的 ConfirmCardView 行内（`item.source == .aiEstimated` 时）追加按钮：

```swift
Button {
    let grams = max(item.grams, 1)
    try? AppContainer.shared.store.saveCustomFood(CustomFood(
        name: item.name,
        nutritionPer100g: NutritionFacts(
            kcal: item.nutrition.kcal * 100 / grams,
            protein: item.nutrition.protein * 100 / grams,
            fat: item.nutrition.fat * 100 / grams,
            carb: item.nutrition.carb * 100 / grams
        )
    ))
} label: {
    Image(systemName: "square.and.arrow.down")
        .accessibilityLabel("存为我的食物")
}
```

- [ ] **Step 7: 写 ProfileView.swift（spec 7.4，含隐私信号）**

```swift
import SwiftUI

enum SettingsKeys {
    static let deepseekApiKey = "deepseekApiKey"
    static let writeBackToHealthKit = "writeBackToHealthKit"
    static let weightUnit = "weightUnit"
}

struct ProfileView: View {
    @AppStorage(SettingsKeys.deepseekApiKey) private var apiKey = ""
    @AppStorage(SettingsKeys.writeBackToHealthKit) private var writeBackToHealthKit = false
    @AppStorage(SettingsKeys.weightUnit) private var weightUnitRaw = WeightUnit.kg.rawValue

    @State private var showingEditGoal = false
    @State private var newWeight: Double?
    @State private var currentGoal: Goal?
    @State private var latestWeight: Double?

    private let store = AppContainer.shared.store
    private let healthKit = AppContainer.shared.healthKit

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kg
    }

    var body: some View {
        NavigationStack {
            List {
                goalSection
                weightSection
                customFoodSection
                settingsSection
                privacySection
            }
            .navigationTitle("我的")
            .onAppear { reload() }
        }
    }

    private var goalSection: some View {
        Section("当前目标") {
            if let goal = currentGoal {
                LabeledContent("目标体重", value: Formatting.weightText(kg: goal.targetWeightKg, unit: weightUnit))
                LabeledContent("开始体重", value: Formatting.weightText(kg: goal.startWeightKg, unit: weightUnit))
                LabeledContent("每日热量", value: "\(Formatting.kcalText(goal.targets.kcal)) kcal")
                LabeledContent("蛋白质 / 脂肪 / 碳水", value: "\(Formatting.gramsText(goal.targets.protein)) / \(Formatting.gramsText(goal.targets.fat)) / \(Formatting.gramsText(goal.targets.carb))")
                LabeledContent("饮水目标", value: "\(Formatting.mlText(goal.waterTargetMl)) ml")
            }
            Button("修改目标") { showingEditGoal = true }
                .accessibilityIdentifier("editGoal")
        }
        .sheet(isPresented: $showingEditGoal) {
            EditGoalSheet(store: store, current: currentGoal)
        }
    }

    private var weightSection: some View {
        Section("体重记录") {
            if let latestWeight {
                LabeledContent("最新体重", value: Formatting.weightText(kg: latestWeight, unit: weightUnit))
            }
            HStack {
                TextField("新体重 (kg)", value: $newWeight, format: .number)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("newWeightField")
                Button("记录") {
                    guard let newWeight else { return }
                    try? store.addWeight(kg: newWeight, date: .now)
                    if writeBackToHealthKit {
                        Task { try? await healthKit.saveWeight(kg: newWeight, date: .now) }
                    }
                    self.newWeight = nil
                    reload()
                }
                .disabled(newWeight == nil)
            }
        }
    }

    private var customFoodSection: some View {
        Section {
            NavigationLink("自定义食物") {
                CustomFoodsView(store: store)
            }
        }
    }

    private var settingsSection: some View {
        Section("设置") {
            LabeledContent("DeepSeek API Key") {
                SecureField("sk-...", text: $apiKey)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("apiKeyField")
            }
            Button("请求 HealthKit 授权") {
                Task { try? await healthKit.requestAuthorization() }
            }
            Toggle("写回 HealthKit（体重/饮水）", isOn: $writeBackToHealthKit)
            Picker("体重单位", selection: $weightUnitRaw) {
                Text("kg").tag(WeightUnit.kg.rawValue)
                Text("斤").tag(WeightUnit.jin.rawValue)
            }
            ShareLink(item: exportFileURL()) {
                Label("导出备份 (JSON)", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var privacySection: some View {
        Section("隐私") {
            Text("数据仅存本机，照片不出设备；照片/语音即用即弃，不留缓存。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func reload() {
        currentGoal = try? store.currentGoal()
        latestWeight = (try? store.weightSamples(limit: 1).first?.weightKg)
            ?? (try? store.profile())?.initialWeightKg
    }

    private func exportFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = "轻卡备份-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = try? store.exportJSON() {
            try? data.write(to: url)  // 用户主动触发的导出，非媒体缓存（spec 4.6 允许）
        }
        return url
    }
}
```

- [ ] **Step 8: RootTabView 我的 Tab 换成 ProfileView**

```swift
ProfileView()
    .tabItem { Label("我的", systemImage: "person.crop.circle") }
```

- [ ] **Step 9: 运行确认通过**

Run: 同 Step 2 命令
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: 全量回归（所有单元测试）**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 11: Commit**

```bash
git add LightCal/UI/Profile LightCal/UI/Logging/ConfirmCardView.swift LightCal/UI/Formatting.swift LightCal/UI/RootTabView.swift LightCalTests
git commit -m "feat: 我的页（目标留档/自定义食物/设置/导出/隐私说明）"
```

---

### Task 20: 构建安装文档与 IPA 导出脚本

**Files:**
- Create: `scripts/export-ipa.sh`
- Create: `docs/INSTALL.md`
- Modify: `README.md`（补安装文档链接）

**Interfaces:**
- Consumes: 全部（收官任务）
- Produces: `scripts/export-ipa.sh`（一键无签名导出 `build/LightCal.ipa`）、`docs/INSTALL.md`（LiveContainer 安装步骤）

- [ ] **Step 1: 写 scripts/export-ipa.sh**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/LightCal.xcarchive build/Payload build/LightCal.ipa
xcodebuild -project LightCal.xcodeproj -scheme LightCal -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/LightCal.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive

APP_DIR=$(find build/LightCal.xcarchive/Products/Applications -maxdepth 1 -name "*.app" | head -1)
mkdir -p build/Payload
cp -R "$APP_DIR" build/Payload/
(cd build && zip -rq LightCal.ipa Payload)
rm -rf build/Payload
echo "✅ IPA 已生成: build/LightCal.ipa"
```

```bash
chmod +x scripts/export-ipa.sh
```

- [ ] **Step 2: 写 docs/INSTALL.md**

````markdown
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
````

- [ ] **Step 3: 更新 README.md**

```markdown
# 轻卡 LightCal

个人自用的 iOS 减脂打卡 App：拍照 / 语音 / 文字快速记录饮食，自动统计热量与蛋白质、脂肪、碳水，对照目标计算缺口并给出补充食物建议；运动消耗自动读取 Apple Health；根据历史摄入与消耗趋势动态估算减脂速率与目标达成时间。

- **平台**：iOS 17+ 原生（SwiftUI），仅个人自用
- **隐私**：数据仅存本机，照片不出设备，媒体即用即弃
- **状态**：设计完成，实现未开始

## 文档

- 设计文档：[docs/superpowers/specs/2026-08-20-diet-tracker-design.md](docs/superpowers/specs/2026-08-20-diet-tracker-design.md)
- 实现计划：[docs/superpowers/plans/2026-08-20-lightcal-implementation.md](docs/superpowers/plans/2026-08-20-lightcal-implementation.md)
- 安装指南：[docs/INSTALL.md](docs/INSTALL.md)

## 构建与测试

```bash
xcodegen generate            # 生成工程
./scripts/ensure-simulator.sh  # 首次准备模拟器
xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```
```

- [ ] **Step 4: 全量回归（全部测试）**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `** TEST SUCCEEDED **`（单元 + UI 全绿）

- [ ] **Step 5: 提交并推送**

```bash
git add scripts/export-ipa.sh docs/INSTALL.md README.md
git commit -m "docs: 安装指南与 IPA 导出脚本"
git push
```

---

## 计划自查记录（writing-plans 自审，已修正）

1. **Spec 覆盖**：spec 第 3 节 → Task 2/8/9；第 4 节 → Task 3/4/5/6/7/13/14/17；第 5 节 → Task 8/10/16；第 6 节 → Task 11/16；第 7 节 → Task 15/16/17/18/19（含设计令牌与隐私信号）；第 8 节 → 全部任务的模块划分；第 9 节 → 各任务测试步骤；第 10 节 → Task 20；第 11 节（YAGNI）→ 均未实现。无遗漏。
2. **占位符扫描**：无 TBD/TODO；Task 16 refresh 的示意残留已改写为完整实现；所有代码步骤均含可编译代码。
3. **类型一致性**：`NutritionFacts.scaled`、`MealKind`、`ParsedFoodItem`、`CompletedFoodItem`、`LogDraft`、`WeightSample`、`DailyTargets`、`GapAnalysis.primaryNeed`（阈值 `nearLimitKcal=200`、低脂阈值 5.0 与测试用例一致）、`ConfirmCardView.onSave([CompletedFoodItem])` 与 `TodayViewModel.saveDraft(items:)` 签名统一；Task 13 测试不再引用 Task 14 的 `VisionFoodRecognizerError`。
4. **已知环境依赖**：xcodegen 需 brew 安装；iOS 模拟器运行时需首次下载（`ensure-simulator.sh`）；真机相关能力（HealthKit 授权、相机、语音、LiveContainer）以手工清单覆盖，不阻塞 CI。




