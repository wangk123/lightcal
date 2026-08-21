# 今日记录增强（饮水时间线/左滑删除/肉类细分/图标完善）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把饮水记录并入「今日记录」时间线（每条单独一行、与食物按时间混排），今日记录支持左滑删除，内置食物库细化肉类部位并新增全麦面包，修复并扩充食物图标映射。

**Architecture:** 数据层只加一个删除操作（`deleteWaterItem`）+ 饮水按时间排序；展示逻辑集中在 `TodayViewModel` 新增的 `TimelineEntry` 枚举（合并食物/饮水、承载显示文案），视图把今日页从 ScrollView 卡片改为 `List(.insetGrouped)` 以获得原生 `swipeActions` 左滑删除；图标保持「先命中先返回」结构，仅重排关键词表；食物库是打包 JSON，纯数据追加。

**Tech Stack:** SwiftUI（iOS 17+）、SwiftData、Xcode 26.6、xcodebuild test（iPhone 16 模拟器）。

**Spec:** `docs/superpowers/specs/2026-08-21-today-log-improvements-design.md`

## Global Constraints

- SWIFT_VERSION 6.0、SWIFT_STRICT_CONCURRENCY complete、SWIFT_DEFAULT_ACTOR_ISOLATION nonisolated（project.yml）——新增代码必须过严格并发检查，`TodayViewModel` 保持 `@MainActor @Observable`。
- 图标纪律：SF Symbols、不用 emoji；「水」精确名 → `drop.fill`；兜底 `fork.knife`（spec 2.4）。
- 文案纪律：时间线空态文案「还没有记录，点右上角 + 开始打卡」、水卡文案「500 / 2100 ml」、食物行「鸡胸肉 100g」与「133 kcal」文本形态保持不变（UI 测试依赖，spec 2.1/5.2）。
- accessibilityIdentifier 不变：`addEntry`、`waterQuick250`、`waterQuick500`、`logTextField`、`parseAndConfirm`、`saveDraft`。
- 测试命令（全程用这一条，`-only-testing` 用于单测/单 UI 测试提速）：
  ```bash
  xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
- 每任务一个 commit，message 用 `feat:` / `fix:` / `test:` 前缀（仓库现有惯例为中文描述）。
- foods.json 格式：3 空格缩进、`ensure_ascii` 不启用（文件中直接是中文）、条目字段序 `name, aliases, nutritionPer100g{kcal,protein,fat,carb}, defaultServingGrams`。编辑后必须能通过 `python3 -m json.tool` 校验。

---

### Task 0: 基线验证（无代码改动）

**Files:** 无

**Interfaces:**
- Consumes: 无
- Produces: 基线结论（哪些测试当前红/绿），后续任务以「红线修复 + 无新增红线」为通过标准。

- [ ] **Step 1: 跑全部单元测试**

Run:
```bash
xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LightCalTests 2>&1 | tee /tmp/lightcal-baseline-unit.log
```
Expected: 全绿（README 称 v1 全绿；如有红线记录在案并在实现对应任务时修复，不允许带病推进）。

- [ ] **Step 2: 跑两个今日页 UI 测试**

Run:
```bash
xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LightCalUITests/TodayFlowUITests 2>&1 | tee /tmp/lightcal-baseline-ui.log
```
Expected: **实测已确认（2026-08-21 实机诊断）**：`testWaterQuickAddAndTextLogging` 红，第 28/29 行两处断言失败（「鸡胸肉 100g」与「133 kcal」）。逐层排查（录屏帧 + 元素树 + 文件埋点）后的完整根因有三层，全部由本计划后续任务修复：

1. **确认卡片呈现竞态（主因）**：录入 sheet 关闭时链式触发确认 sheet，SwiftUI 呈现竞态导致确认卡片不出现或出现即消失，`保存` 按钮的 onSave 从未执行 → 记录从未落库。Task 6 用「确认卡片内嵌录入 sheet 的 NavigationStack」根治。
2. **@Observable 重渲染丢失**：即使保存成功（0 kcal 的 AI 估算条目不改变任何被 body 读取的可观察属性），`refresh()` 后视图不重渲染，时间线停留在旧状态。Task 5 把 timeline 移入 ViewModel（每次 refresh 必然改写 timeline）根治。
3. **鸡胸肉不在库**：营养为 0，断言「133 kcal」必失败。Task 1 入库后转绿（鸡胸肉 133 kcal 命中内置库）。

执行时只需记录「2 处失败、根因如上」即可，不必重新排查；修复顺序 Task 1 → 5 → 6，Task 6 完成后两处断言同时转绿。

- [ ] **Step 3: 记录基线并提交**

无代码改动则不 commit；把基线结论写进本任务的执行记录，供后续任务比对。

---

### Task 1: 食物库细化——9 条细分肉 + 全麦面包（TDD）

**Files:**
- Modify: `LightCal/Resources/foods.json`
- Test: `LightCalTests/FoodDatabaseTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: 库内新增可精确匹配的条目名：`鸡胸肉`、`鸡腿肉`、`鸡翅`、`牛里脊`、`牛腩`、`肥牛卷`、`猪里脊`、`猪五花肉`、`猪排骨`、`全麦面包`；别名 `鸡胸→鸡胸肉`、`排骨/肋排/小排→猪排骨`、`五花肉→猪五花肉`、`全麦吐司→全麦面包`；`鸡肉` 不再含「鸡胸」别名；总条目 232。后续 Task 5 的 UI 测试「133 kcal」依赖 `鸡胸肉` 入库。

- [ ] **Step 1: 写失败的测试**

在 `LightCalTests/FoodDatabaseTests.swift` 的 `FoodDatabaseTests` 类内（`testSearchByKeyword` 之后）追加三个测试方法：

```swift
    func testRefinedMeatEntriesMatchChineseFoodTable() throws {
        let db = try FoodDatabase.loadFromBundle()
        let expected: [(name: String, kcal: Double, protein: Double, fat: Double, carb: Double)] = [
            ("鸡胸肉", 133, 19.4, 5.0, 2.5),
            ("鸡腿肉", 181, 16.0, 13.0, 0.0),
            ("鸡翅", 194, 17.4, 11.8, 4.6),
            ("牛里脊", 107, 22.2, 0.9, 2.4),
            ("牛腩", 332, 17.1, 29.3, 0.0),
            ("肥牛卷", 250, 19.1, 18.7, 0.0),
            ("猪里脊", 155, 20.2, 7.9, 0.7),
            ("猪五花肉", 568, 7.7, 59.0, 0.9),
            ("猪排骨", 278, 16.7, 23.1, 0.7),
            ("全麦面包", 246, 8.6, 2.6, 46.3),
        ]
        for entry in expected {
            guard let record = db.match(exact: entry.name) else {
                XCTFail("缺少条目 \(entry.name)")
                continue
            }
            XCTAssertEqual(record.nutritionPer100g.kcal, entry.kcal, accuracy: 0.001, "\(entry.name) kcal")
            XCTAssertEqual(record.nutritionPer100g.protein, entry.protein, accuracy: 0.001, "\(entry.name) protein")
            XCTAssertEqual(record.nutritionPer100g.fat, entry.fat, accuracy: 0.001, "\(entry.name) fat")
            XCTAssertEqual(record.nutritionPer100g.carb, entry.carb, accuracy: 0.001, "\(entry.name) carb")
        }
    }

    func testAliasOwnershipAfterRefinement() throws {
        let db = try FoodDatabase.loadFromBundle()
        XCTAssertEqual(db.match(exact: "鸡胸")?.name, "鸡胸肉")
        XCTAssertEqual(db.match(exact: "排骨")?.name, "猪排骨")
        XCTAssertEqual(db.match(exact: "五花肉")?.name, "猪五花肉")
        XCTAssertEqual(db.match(exact: "全麦吐司")?.name, "全麦面包")
        XCTAssertEqual(db.match(exact: "鸡肉")?.name, "鸡肉")  // 通用条目保留
        XCTAssertNil(db.match(exact: "里脊"))                  // 裸里脊有歧义，不进别名
    }

    func testFoodCountAfterRefinement() throws {
        let db = try FoodDatabase.loadFromBundle()
        XCTAssertEqual(db.foods.count, 232)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FoodDatabaseTests`
Expected: FAIL——三个新用例分别报「缺少条目 鸡胸肉」「match 返回 nil / 名称不符」「223 != 232」。

- [ ] **Step 3: 修改 foods.json**

三处编辑（用 edit 工具，old_string 必须逐字匹配文件）：

3a. 「鸡肉」移除鸡胸别名：
```
{
   "name": "鸡肉",
   "aliases": [
    "鸡胸"
   ],
```
改为：
```
{
   "name": "鸡肉",
   "aliases": [],
```

3b. 删除整个「排骨」条目（含前导逗号与换行，保持数组语法合法）：
```
  },
  {
   "name": "排骨",
   "aliases": [],
   "nutritionPer100g": {
    "kcal": 321,
    "protein": 22.0,
    "fat": 25.0,
    "carb": 0.0
   },
   "defaultServingGrams": null
  }
```
改为：
```
  }
```

3c. 在文件末尾「苹果酒」条目之后追加 10 个新条目。把：
```
  {
   "name": "苹果酒",
   "aliases": [],
   "nutritionPer100g": {
    "kcal": 49,
    "protein": 0.0,
    "fat": 0.0,
    "carb": 5.0
   },
   "defaultServingGrams": null
  }
 ]
}
```
替换为（注意 3 空格缩进、每条目后逗号）：
```
  {
   "name": "苹果酒",
   "aliases": [],
   "nutritionPer100g": {
    "kcal": 49,
    "protein": 0.0,
    "fat": 0.0,
    "carb": 5.0
   },
   "defaultServingGrams": null
  },
  {
   "name": "鸡胸肉",
   "aliases": [
    "鸡胸",
    "鸡胸脯肉"
   ],
   "nutritionPer100g": {
    "kcal": 133,
    "protein": 19.4,
    "fat": 5.0,
    "carb": 2.5
   },
   "defaultServingGrams": null
  },
  {
   "name": "鸡腿肉",
   "aliases": [
    "鸡腿",
    "琵琶腿"
   ],
   "nutritionPer100g": {
    "kcal": 181,
    "protein": 16.0,
    "fat": 13.0,
    "carb": 0.0
   },
   "defaultServingGrams": null
  },
  {
   "name": "鸡翅",
   "aliases": [
    "鸡翅中",
    "鸡翅根"
   ],
   "nutritionPer100g": {
    "kcal": 194,
    "protein": 17.4,
    "fat": 11.8,
    "carb": 4.6
   },
   "defaultServingGrams": null
  },
  {
   "name": "牛里脊",
   "aliases": [
    "牛柳"
   ],
   "nutritionPer100g": {
    "kcal": 107,
    "protein": 22.2,
    "fat": 0.9,
    "carb": 2.4
   },
   "defaultServingGrams": null
  },
  {
   "name": "牛腩",
   "aliases": [
    "牛腩肉"
   ],
   "nutritionPer100g": {
    "kcal": 332,
    "protein": 17.1,
    "fat": 29.3,
    "carb": 0.0
   },
   "defaultServingGrams": null
  },
  {
   "name": "肥牛卷",
   "aliases": [
    "肥牛",
    "肥牛片"
   ],
   "nutritionPer100g": {
    "kcal": 250,
    "protein": 19.1,
    "fat": 18.7,
    "carb": 0.0
   },
   "defaultServingGrams": null
  },
  {
   "name": "猪里脊",
   "aliases": [
    "猪柳"
   ],
   "nutritionPer100g": {
    "kcal": 155,
    "protein": 20.2,
    "fat": 7.9,
    "carb": 0.7
   },
   "defaultServingGrams": null
  },
  {
   "name": "猪五花肉",
   "aliases": [
    "五花肉",
    "五花"
   ],
   "nutritionPer100g": {
    "kcal": 568,
    "protein": 7.7,
    "fat": 59.0,
    "carb": 0.9
   },
   "defaultServingGrams": null
  },
  {
   "name": "猪排骨",
   "aliases": [
    "排骨",
    "肋排",
    "小排"
   ],
   "nutritionPer100g": {
    "kcal": 278,
    "protein": 16.7,
    "fat": 23.1,
    "carb": 0.7
   },
   "defaultServingGrams": null
  },
  {
   "name": "全麦面包",
   "aliases": [
    "全麦吐司",
    "全麦土司"
   ],
   "nutritionPer100g": {
    "kcal": 246,
    "protein": 8.6,
    "fat": 2.6,
    "carb": 46.3
   },
   "defaultServingGrams": null
  }
 ]
}
```

校验：`python3 -m json.tool LightCal/Resources/foods.json > /dev/null && echo OK`（同时确认 `db.foods.count` 应为 232）。

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FoodDatabaseTests -only-testing:LightCalTests/FoodDBCoverageTests`
Expected: PASS（覆盖率测试仍绿：通用条目保留，Vision 标签网不破）。

- [ ] **Step 5: Commit**

```bash
git add LightCal/Resources/foods.json LightCalTests/FoodDatabaseTests.swift
git commit -m "feat: 食物库肉类按部位细分+全麦面包（223→232 条）"
```

---

### Task 2: 食物图标关键词表重排（TDD）

**Files:**
- Modify: `LightCal/UI/FoodIcon.swift`
- Test: `LightCalTests/FoodIconTests.swift`

**Interfaces:**
- Consumes: 无（`FoodIcon.symbol(for:)` 签名不变）
- Produces: 新的关键词分组顺序（spec 2.4.3 表）与「水」精确名特判；后续 Task 5/6 通过 `FoodIcon.symbol(for:)` 与 `drop.fill` 使用。

- [ ] **Step 1: 写失败的测试**

在 `LightCalTests/FoodIconTests.swift` 追加四个测试方法（保留既有 6 个测试不动）：

```swift
    func testCompoundWordsBeatSingleCharKeywords() {
        XCTAssertEqual(FoodIcon.symbol(for: "鸡蛋"), "circle.hexagongrid.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛奶"), "cup.and.saucer.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛油果"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛油果酱"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛角包"), "takeoutbag.and.cup.and.straw.fill")
    }

    func testRemovedBareKeywords() {
        // 裸「甜」已删：甜菜根/甜瓜 归蔬菜而非甜品
        XCTAssertEqual(FoodIcon.symbol(for: "甜菜根"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "甜瓜"), "leaf.fill")
        // 裸「水」已删：水果 归水果而非饮品
        XCTAssertEqual(FoodIcon.symbol(for: "水果"), "carrot.fill")
        // 裸「卷」已删：肥牛卷 归肉而非主食
        XCTAssertEqual(FoodIcon.symbol(for: "肥牛卷"), "fork.knife")
        // 裸「排」已删：牛排/猪排骨 仍按具体词归肉
        XCTAssertEqual(FoodIcon.symbol(for: "牛排"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "猪排骨"), "fork.knife")
    }

    func testExpandedCoverage() {
        XCTAssertEqual(FoodIcon.symbol(for: "吐司"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "蛤蜊"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "生蚝"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "辣椒"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "洋葱"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "椰子"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "石榴"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "卡布奇诺"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "拿铁"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "全麦面包"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "鸡胸肉"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "鸡腿肉"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "炒饭"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "麦片"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "番茄"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "海鲜"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "栗子"), "circle.grid.cross.fill")
    }

    func testWaterExactName() {
        XCTAssertEqual(FoodIcon.symbol(for: "水"), "drop.fill")
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FoodIconTests`
Expected: FAIL——鸡蛋/牛奶/牛油果/牛角包当前都返回 `fork.knife`；甜瓜/水果/肥牛卷/炒饭/麦片/番茄/海鲜/水等与期望不符。

- [ ] **Step 3: 实现——整体替换 `FoodIcon.swift` 内容**

```swift
import SwiftUI

/// 食物类别 → SF Symbol 图标（spec 7.6 图标纪律：SF Symbols，不用 emoji）
/// 顺序即优先级：先命中先返回。具体词在前，单字泛词在后（spec 2026-08-21 §2.4）。
enum FoodIcon {
    private static let symbolByKeyword: [(keywords: [String], symbol: String)] = [
        // 甜品（先于蛋/糖类单字，保证 蛋糕/蛋挞 归甜品）
        (["蛋糕", "巧克力", "饼干", "糖果", "甜甜圈", "爆米花", "布丁", "雪芭", "布朗尼", "玛芬", "司康", "挞", "派", "冰淇淋", "太妃糖", "棉花糖", "甜品", "甜筒"], "birthday.cake.fill"),
        // 饮品（不用裸「水」，避免 水果/西瓜 误判）
        (["茶", "咖啡", "卡布奇诺", "拿铁", "果汁", "汽水", "啤酒", "葡萄酒", "矿泉", "纯净水", "酒", "蛋奶酒"], "wineglass.fill"),
        // 坚果（先于裸「果」）
        (["花生", "核桃", "腰果", "杏仁", "坚果", "栗子"], "circle.grid.cross.fill"),
        // 水果（牛油果等具体词先于肉组「牛」；裸「果」兜底）
        (["牛油果", "苹果", "香蕉", "橙", "梨", "桃", "莓", "葡萄", "西瓜", "菠萝", "芒果", "猕猴桃", "柠檬", "樱桃", "椰子", "石榴", "李子", "杏", "橄榄", "枣", "覆盆子", "柚子", "青柠", "橘子", "荔枝", "榴莲", "柿子", "番石榴", "果"], "carrot.fill"),
        // 乳品（先于肉组「牛」）
        (["牛奶", "酸奶", "乳酪", "芝士", "黄油", "奶"], "cup.and.saucer.fill"),
        // 主食烘焙（牛角包先于肉组「牛」；煎蛋卷先于蛋组「蛋」）
        (["牛角包", "米饭", "馒头", "包子", "面包", "吐司", "法棍", "恰巴塔", "年糕", "塔可", "热狗", "意大利辣肠", "三明治", "汉堡", "披萨", "饺子", "馄饨", "煎饼", "卷饼", "春卷", "煎蛋卷", "格兰诺拉", "团子", "面条", "饼", "粥", "燕麦", "玉米", "薯", "土豆", "粉", "米", "面", "麦", "饭", "包"], "takeoutbag.and.cup.and.straw.fill"),
        // 蛋
        (["鸡蛋", "鸭蛋", "鹌鹑蛋", "蛋"], "circle.hexagongrid.fill"),
        // 肉（不用裸「排」；牛/猪/羊单字安全：牛角包/牛奶/牛油果已被前置组截获）
        (["鸡", "鸭", "鹅", "火鸡", "牛", "猪", "羊", "培根", "火腿", "香肠", "肉丸", "牛排", "排骨", "肉"], "fork.knife"),
        // 海鲜
        (["鱼", "虾", "蟹", "贝", "海鲜", "蛤蜊", "生蚝", "青口", "扇贝", "鱿鱼", "章鱼", "三文鱼", "金枪鱼", "寿司", "刺身", "海苔", "紫菜"], "fish.fill"),
        // 蔬菜
        (["西兰花", "菠菜", "生菜", "芹菜", "芦笋", "黄瓜", "萝卜", "茄子", "蘑菇", "豆腐", "豆芽", "辣椒", "洋葱", "大蒜", "西葫芦", "洋蓟", "沙拉", "卷心菜", "菜", "瓜", "豆", "茄"], "leaf.fill"),
        // 汤羹
        (["汤", "锅", "煲", "咖喱", "炖"], "flame.fill"),
    ]

    static func symbol(for foodName: String) -> String {
        if foodName == "水" { return "drop.fill" }  // 库内唯一「水」，精确名特判
        for entry in symbolByKeyword where entry.keywords.contains(where: { foodName.contains($0) }) {
            return entry.symbol
        }
        return "fork.knife"
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FoodIconTests`
Expected: PASS（含既有 6 个测试）。

- [ ] **Step 5: Commit**

```bash
git add LightCal/UI/FoodIcon.swift LightCalTests/FoodIconTests.swift
git commit -m "fix: 食物图标关键词重排（修复鸡蛋/牛奶/牛油果/牛角包误判+扩充覆盖）"
```

---

### Task 3: DataStore——饮水删除 + 饮水按时间排序（TDD）

**Files:**
- Modify: `LightCal/Models/DataStore.swift`
- Test: `LightCalTests/DataStoreTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `func deleteWaterItem(_ item: WaterLogItem) throws`（与 `deleteLogItem` 对称）；`waterItems(on:)` 返回按 `createdAt` 升序的数组。Task 5 的 `delete(entry:)` 依赖 `deleteWaterItem`。

- [ ] **Step 1: 写失败的测试**

在 `LightCalTests/DataStoreTests.swift` 的 `DataStoreTests` 类内（`testDaySummaryAggregatesNutritionAndWater` 之后）追加：

```swift
    func testWaterItemsSortedByCreatedAt() throws {
        let store = try makeStore()
        try store.addWater(ml: 250, date: day())
        try store.addWater(ml: 500, date: day())
        let items = try store.waterItems(on: day())
        XCTAssertEqual(items.map(\.amountMl), [250, 500])
    }

    func testDeleteWaterItem() throws {
        let store = try makeStore()
        try store.addWater(ml: 250, date: day())
        let items = try store.waterItems(on: day())
        XCTAssertEqual(items.count, 1)
        try store.deleteWaterItem(items[0])
        XCTAssertTrue(try store.waterItems(on: day()).isEmpty)
        // 删除后日汇总联动归零
        XCTAssertEqual(try store.daySummary(day()).waterMl, 0, accuracy: 0.001)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/DataStoreTests`
Expected: FAIL——`testDeleteWaterItem` 编译不过（`deleteWaterItem` 不存在）；`testWaterItemsSortedByCreatedAt` 因无排序（当前按插入序，250 在前则通过）若通过不意外，重点看编译错误。

- [ ] **Step 3: 实现**

`LightCal/Models/DataStore.swift`，把 `waterItems(on:)` 改为带排序：

```swift
    func waterItems(on day: Date) throws -> [WaterLogItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try container.mainContext.fetch(FetchDescriptor<WaterLogItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }
```

并在 `addWater` 之后新增删除方法：

```swift
    func deleteWaterItem(_ item: WaterLogItem) throws {
        container.mainContext.delete(item)
        try container.mainContext.save()
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/DataStoreTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LightCal/Models/DataStore.swift LightCalTests/DataStoreTests.swift
git commit -m "feat: 饮水记录支持删除并按时间排序（DataStore）"
```

---

### Task 4: Formatting.timeText（TDD）

**Files:**
- Modify: `LightCal/UI/Formatting.swift`
- Test: `LightCalTests/TodayViewModelTests.swift`（`FormattingTests` 类）

**Interfaces:**
- Consumes: 无
- Produces: `static func timeText(_ date: Date) -> String`——24 小时制 `HH:mm`，与时区无关的确定性输出（Task 6 时间线行使用）。

- [ ] **Step 1: 写失败的测试**

在 `LightCalTests/TodayViewModelTests.swift` 的 `FormattingTests` 类内（`testMlText` 之后）追加：

```swift
    func testTimeText() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 14, minute: 30))!
        XCTAssertEqual(Formatting.timeText(date), "14:30")
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FormattingTests`
Expected: FAIL——编译错误（`timeText` 不存在）。

- [ ] **Step 3: 实现**

在 `LightCal/UI/Formatting.swift` 的 `Formatting` 枚举内（`mlText` 之后）新增：

```swift
    /// 24 小时制 HH:mm（dateFormat 模式与用户时区结合，输出确定性）
    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
```

（每次调用新建 DateFormatter 是为了绕开 strict concurrency 下静态非 Sendable 的问题；时间线行数少，无性能顾虑。）

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/FormattingTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LightCal/UI/Formatting.swift LightCalTests/TodayViewModelTests.swift
git commit -m "feat: Formatting.timeText（HH:mm 时间显示）"
```

---

### Task 5: TodayViewModel——时间线合并 + 删除（TDD）

**Files:**
- Modify: `LightCal/UI/Today/TodayViewModel.swift`
- Test: `LightCalTests/TodayViewModelTests.swift`

**Interfaces:**
- Consumes: Task 3 的 `deleteWaterItem`、Task 4 的 `Formatting.timeText`（间接）、Task 2 的 `FoodIcon.symbol(for:)`（间接）
- Produces:
  - `enum TimelineEntry: Identifiable`（同文件顶层，`import SwiftData` 提供 `PersistentIdentifier`），case `.food(FoodLogItem)` / `.water(WaterLogItem)`，属性：`id`、`createdAt`、`meal`（食物=原餐次，饮水="饮水"）、`icon`（食物=FoodIcon.symbol，饮水="drop.fill"）、`titleText`（食物="名称 100g"，饮水="250 ml"）、`isAIEstimated: Bool`、`kcalText: String?`（饮水为 nil）
  - `TodayViewModel.private(set) var timeline: [TimelineEntry]`，`refresh()` 末尾组装，按 `createdAt` 升序稳定排序
  - `func delete(entry: TimelineEntry) async`——食物走 `deleteLogItem`、饮水走 `deleteWaterItem`，随后 `await refresh()`

- [ ] **Step 1: 写失败的测试**

在 `LightCalTests/TodayViewModelTests.swift` 的 `TodayViewModelTests` 类内（`testSuggestionsConstrainedToPresetFoods` 之后）追加：

```swift
    func testTimelineMergesFoodAndWaterByCreatedAt() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 250)                       // 第一条：饮水
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()                             // 第二条：食物
        vm.addWater(ml: 500)                       // 第三条：饮水
        await vm.refresh()

        XCTAssertEqual(vm.timeline.count, 3)
        guard case .water(let w1) = vm.timeline[0],
              case .food(let food) = vm.timeline[1],
              case .water(let w2) = vm.timeline[2] else {
            return XCTFail("时间线顺序应为：水250 → 食物 → 水500")
        }
        XCTAssertEqual(w1.amountMl, 250)
        XCTAssertEqual(w2.amountMl, 500)
        XCTAssertEqual(food.name, "鸡胸肉")
    }

    func testTimelineEntryDisplayProperties() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 250)
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()

        guard let waterEntry = vm.timeline.first, case .water = waterEntry else { return XCTFail("第一条应为饮水") }
        XCTAssertEqual(waterEntry.titleText, "250 ml")
        XCTAssertEqual(waterEntry.meal, "饮水")
        XCTAssertEqual(waterEntry.icon, "drop.fill")
        XCTAssertNil(waterEntry.kcalText)

        guard let foodEntry = vm.timeline.last, case .food = foodEntry else { return XCTFail("最后一条应为食物") }
        XCTAssertEqual(foodEntry.titleText, "鸡胸肉 100g")
        XCTAssertEqual(foodEntry.kcalText, "133")
        XCTAssertFalse(foodEntry.isAIEstimated)
        XCTAssertEqual(foodEntry.icon, "fork.knife")
    }

    func testDeleteFoodAndWaterEntries() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        vm.addWater(ml: 250)
        await vm.refresh()
        XCTAssertEqual(vm.timeline.count, 2)

        // 删饮水：时间线只剩食物，饮水汇总归零
        if case .water = vm.timeline[1] {} else { return XCTFail("第二条应为饮水") }
        await vm.delete(entry: vm.timeline[1])
        XCTAssertEqual(vm.timeline.count, 1)
        XCTAssertEqual(vm.summary.waterMl, 0, accuracy: 0.001)

        // 删食物：时间线空，营养汇总归零
        await vm.delete(entry: vm.timeline[0])
        XCTAssertTrue(vm.timeline.isEmpty)
        XCTAssertEqual(vm.summary.totalNutrition.kcal, 0, accuracy: 0.001)
    }

    func testEmptyTimeline() async throws {
        let vm = try await makeViewModel()
        XCTAssertTrue(vm.timeline.isEmpty)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/TodayViewModelTests`
Expected: FAIL——编译错误（`TimelineEntry`、`vm.timeline`、`vm.delete(entry:)` 不存在）。

- [ ] **Step 3: 实现**

`LightCal/UI/Today/TodayViewModel.swift` 两处修改：

3a. 文件头 `import Foundation`、`import Observation` 之后加 `import SwiftData`；文件末尾（`TodayViewModel` 类之后）新增 `TimelineEntry`：

```swift
/// 今日记录时间线条目：食物与饮水统一建模（spec 2026-08-21 §3.2）
enum TimelineEntry: Identifiable {
    case food(FoodLogItem)
    case water(WaterLogItem)

    var id: PersistentIdentifier {
        switch self {
        case .food(let item): item.persistentModelID
        case .water(let item): item.persistentModelID
        }
    }

    var createdAt: Date {
        switch self {
        case .food(let item): item.createdAt
        case .water(let item): item.createdAt
        }
    }

    /// 行首胶囊标签：食物=餐次，饮水="饮水"
    var meal: String {
        switch self {
        case .food(let item): item.meal
        case .water: "饮水"
        }
    }

    var icon: String {
        switch self {
        case .food(let item): FoodIcon.symbol(for: item.name)
        case .water: "drop.fill"
        }
    }

    /// 主体文案：食物="鸡胸肉 100g"，饮水="250 ml"
    var titleText: String {
        switch self {
        case .food(let item): "\(item.name) \(Formatting.gramsText(item.grams))"
        case .water(let item): "\(Formatting.mlText(item.amountMl)) ml"
        }
    }

    var isAIEstimated: Bool {
        if case .food(let item) = self { return item.source == NutritionSource.aiEstimated.rawValue }
        return false
    }

    /// 行尾热量文案；饮水无热量返回 nil
    var kcalText: String? {
        if case .food(let item) = self { return Formatting.kcalText(item.nutrition.kcal) }
        return nil
    }
}
```

3b. `TodayViewModel` 类内新增属性与两个方法：

```swift
    private(set) var timeline: [TimelineEntry] = []
```

`refresh()` 末尾（`prediction = ...` 之后）追加：

```swift
        let foods = (try? store.logItems(on: now)) ?? []
        let waters = (try? store.waterItems(on: now)) ?? []
        timeline = (foods.map(TimelineEntry.food) + waters.map(TimelineEntry.water))
            .sorted { $0.createdAt < $1.createdAt }
```

`saveDraft` 之后新增：

```swift
    func delete(entry: TimelineEntry) async {
        switch entry {
        case .food(let item): try? store.deleteLogItem(item)
        case .water(let item): try? store.deleteWaterItem(item)
        }
        await refresh()
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests/TodayViewModelTests`
Expected: PASS（`makeViewModel` 里 `refresh()` 已含 timeline 组装；既有用例不受影响）。

- [ ] **Step 5: Commit**

```bash
git add LightCal/UI/Today/TodayViewModel.swift LightCalTests/TodayViewModelTests.swift
git commit -m "feat: 时间线合并食物与饮水+逐条删除（TimelineEntry）"
```

---

### Task 6: 今日页 List 化 + 时间线渲染 + 左滑删除 + 录入 sheet 架构修复（UI 测试先行）

**Files:**
- Modify: `LightCal/UI/Today/TodayDashboardView.swift`（List 化 + 时间线 + 左滑 + sheet 接线）
- Modify: `LightCal/UI/Logging/EntryPointSheet.swift`（确认卡片内嵌同一 NavigationStack，消灭链式 sheet 竞态）
- Modify: `LightCal/UI/Logging/ConfirmCardView.swift`（去掉自带 NavigationStack，改为内嵌使用）
- Test: `LightCalUITests/TodayFlowUITests.swift`（新增左滑删除用例 + 既有用例补滚动）

**Interfaces:**
- Consumes: Task 5 的 `viewModel.timeline`、`TimelineEntry` 全部属性、`await viewModel.delete(entry:)`；Task 4 的 `Formatting.timeText`
- Produces: `EntryPointSheet(onSave: ([CompletedFoodItem], MealKind) -> Void)`（接口由 `onDraft` 改为 `onSave`，餐次随回调返回）；`ConfirmCardView(draft:meal:onSave:onCancel:)`（新增 `onCancel`）；今日页 `List(.insetGrouped)` + 每行 `.swipeActions` 左滑删除。

**背景（必读）**：当前录入流程存在三层缺陷，本任务一并修复（详见 Task 0 基线）：(1) 双 sheet 链式呈现竞态使确认卡片不可达；(2) 保存后无可观察属性变化时视图不重渲染（Task 5 的 timeline 入 VM 已根治）；(3) 鸡胸肉缺库（Task 1 已根治）。因此本任务的实现代码**必须**包含 EntryPointSheet/ConfirmCardView 的结构改造，不是单纯换 List。

- [ ] **Step 1: 写失败的 UI 测试**

1a. 在 `LightCalUITests/TodayFlowUITests.swift` 追加新用例（注意：时间线在 List 底部，List 是懒加载，断言行前必须先 `swipeUp()`；回顶部查水卡前先 `swipeDown()`）：

```swift
    @MainActor
    func testTimelineShowsWaterAndSwipeDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        // 饮水快加后，滚动到底部，时间线出现饮水行（区别于水卡「X / 2100 ml」）
        let water = app.buttons["waterQuick250"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["250 ml"].waitForExistence(timeout: 5))

        // 左滑删除饮水行：时间线行消失；回到顶部后水卡归零
        // 用受控拖拽而非裸 swipeLeft()：窄文本拖距过短低于露出阈值，过短/过长拖拽均不可靠（iOS 26 实测）
        revealSwipeActions(forText: "250 ml", in: app)
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.staticTexts["250 ml"].waitForExistence(timeout: 2))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["0 / 2100 ml"].waitForExistence(timeout: 5))

        // 文字录入食物 → 时间线出现（先滚动）→ 左滑删除 → 回到空态
        app.buttons["addEntry"].tap()
        app.buttons["textEntry"].tap()
        let field = app.textFields["logTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("100g鸡胸肉")
        app.buttons["parseAndConfirm"].tap()
        XCTAssertTrue(app.staticTexts["鸡胸肉"].waitForExistence(timeout: 10))
        app.buttons["saveDraft"].tap()

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 5))
        revealSwipeActions(forText: "鸡胸肉 100g", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["还没有记录，点右上角 + 开始打卡"].waitForExistence(timeout: 5))
    }

    /// 受控左滑露出行尾删除按钮。
    /// 直接对行内文本 `swipeLeft()` 不可靠：窄文本（如「250 ml」约 50pt）拖距太短，低于滑动操作露出阈值，
    /// 按钮不会出现；拖距过长又会触发 `swipeActions(allowsFullSwipe: true)` 直接整行删除、同样看不到按钮。
    /// 这里对整行做约一半宽度的慢速拖拽，稳定露出「删除」。
    private func revealSwipeActions(forText text: String, in app: XCUIApplication) {
        let cell = app.cells.containing(.staticText, identifier: text).firstMatch
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)
    }
}
```

1b. 既有 `testWaterQuickAddAndTextLogging` 中，`app.buttons["saveDraft"].tap()` 之后、时间线断言之前插入一行滚动：

```swift
        app.buttons["saveDraft"].tap()

        // 时间线在页面底部（List 懒加载），先滚动到可见
        app.swipeUp()

        // 时间线出现记录
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalUITests/TodayFlowUITests/testTimelineShowsWaterAndSwipeDelete`
Expected: FAIL——`staticTexts["250 ml"]` 找不到（时间线尚无饮水行；且当前录入流程本身的 sheet 竞态未修）。

- [ ] **Step 3: 实现——整体替换三个视图文件**

3a. `LightCal/UI/Logging/EntryPointSheet.swift` 整体替换为（确认卡片内嵌同一 NavigationStack；`onDraft` 接口改为 `onSave`；`finish` 不再 dismiss）：

```swift
import SwiftUI

struct EntryPointSheet: View {
    /// 保存回调：items 为勾选条目（含营养快照），meal 为用户选择的餐次
    var onSave: ([CompletedFoodItem], MealKind) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: EntryMode? = nil
    @State private var showingCamera = false
    @State private var text = ""
    @State private var isParsing = false
    @State private var errorMessage: String?
    /// 非 nil 时在同一个 NavigationStack 内切换到确认卡片（不触发新的 sheet 呈现，规避 SwiftUI 链式 sheet 竞态）
    @State private var confirmDraft: LogDraft?
    @State private var selectedMeal: MealKind = .lunch

    enum EntryMode { case photo, voice, text }

    var body: some View {
        NavigationStack {
            Group {
                if let draft = confirmDraft {
                    ConfirmCardView(
                        draft: draft,
                        meal: $selectedMeal,
                        onSave: { items in
                            onSave(items, selectedMeal)
                            dismiss()
                        },
                        onCancel: { dismiss() }
                    )
                } else {
                    entryContent
                }
            }
            .navigationTitle(confirmDraft == nil ? "添加食物" : "确认记录")
            .toolbar {
                if confirmDraft == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { data in
                handlePhotoData(data)
            }
            .ignoresSafeArea()
        }
    }

    private var entryContent: some View {
        VStack(spacing: 16) {
            if mode == nil {
                entryButtons
            } else if mode == .text {
                textEntry
            } else if mode == .voice {
                voiceEntry
            }
            if isParsing {
                ProgressView("处理中…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.destructive)
            }
        }
        .padding()
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
            errorMessage = nil
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
        // 不关闭 sheet：在同一 NavigationStack 内切换为确认卡片，避免链式 sheet 呈现竞态
        selectedMeal = draft.suggestedMeal ?? MealKind.suggested(for: .now)
        confirmDraft = draft
    }
}
```

3b. `LightCal/UI/Logging/ConfirmCardView.swift` 整体替换为（去掉自带 NavigationStack，改为依赖宿主的栈；新增 `onCancel`）：

```swift
import SwiftUI

struct ConfirmCardView: View {
    let draft: LogDraft
    @Binding var meal: MealKind
    let onSave: ([CompletedFoodItem]) -> Void
    let onCancel: () -> Void

    @State private var grams: [Double]   // 与 draft.items 平行的可编辑份量
    @State private var selected: Set<Int>  // 勾选保存的食物（默认全选）

    init(draft: LogDraft, meal: Binding<MealKind>,
         onSave: @escaping ([CompletedFoodItem]) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self._meal = meal
        self.onSave = onSave
        self.onCancel = onCancel
        self._grams = State(initialValue: draft.items.map(\.grams))
        self._selected = State(initialValue: Set(draft.items.indices))
    }

    var body: some View {
        List {
            Section("餐次") {
                Picker("餐次", selection: $meal) {
                    ForEach(MealKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("确认食物（勾选要保存的，可修改份量）") {
                ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Button {
                            if selected.contains(index) {
                                selected.remove(index)
                            } else {
                                selected.insert(index)
                            }
                        } label: {
                            Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(index) ? DesignTokens.accent : .secondary)
                                .accessibilityLabel(selected.contains(index) ? "已勾选" : "未勾选")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectItem\(index)")
                        Image(systemName: FoodIcon.symbol(for: item.name))
                            .foregroundStyle(DesignTokens.primary)
                            .frame(width: 26)
                        Text(item.name)
                            .strikethrough(!selected.contains(index))
                            .foregroundStyle(selected.contains(index) ? .primary : .secondary)
                        if item.source == .aiEstimated {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.aiAmber)
                                .accessibilityLabel("AI 估算")
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
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            TextField("克", value: $grams[index], format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            // 营养随份量实时换算（按每100g成分 × 当前克重）
                            let factor = item.grams > 0 ? grams[index] / item.grams : 1
                            Text("\(Formatting.kcalText(item.nutrition.kcal * factor)) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text("蛋白 \(Formatting.gramsText(item.nutrition.protein * factor)) · 脂肪 \(Formatting.gramsText(item.nutrition.fat * factor)) · 碳水 \(Formatting.gramsText(item.nutrition.carb * factor))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
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
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(Self.rescaledItems(draft.items, grams: grams, selected: selected))
                }
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("saveDraft")
            }
        }
    }

    /// 份量修改后按比例重算营养快照，仅保留勾选条目（spec 4.4 可编辑/可选）
    static func rescaledItems(_ items: [CompletedFoodItem], grams: [Double], selected: Set<Int>) -> [CompletedFoodItem] {
        items.indices.compactMap { index in
            guard selected.contains(index), index < grams.count else { return nil }
            let item = items[index]
            let newGrams = grams[index]
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

3c. `LightCal/UI/Today/TodayDashboardView.swift` 整体替换为（List 化 + 时间线走 viewModel + 左滑删除 + 单 sheet 接线）：

```swift
import SwiftUI

struct TodayDashboardView: View {
    @State private var viewModel: TodayViewModel
    @State private var showingEntry = false

    init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section { calorieCard }
                Section { waterCard }
                if !viewModel.suggestions.isEmpty {
                    Section { suggestionContent }
                }
                Section { predictionCard }
                Section("今日记录") { timelineSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background)
            .navigationTitle("今日")
            .task { await viewModel.refresh() }
            .sheet(isPresented: $showingEntry) {
                EntryPointSheet { items, meal in
                    viewModel.selectedMeal = meal
                    viewModel.saveDraft(items: items)
                    showingEntry = false
                    Task { await viewModel.refresh() }
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
    }

    private var suggestionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.suggestions, id: \.name) { suggestion in
                Text("\(suggestion.name) \(Formatting.gramsText(suggestion.grams)) · \(Formatting.kcalText(suggestion.nutrition.kcal)) kcal")
                    .font(.callout)
            }
            if !viewModel.hasPresets {
                Text("建议来源于全部食物库。去「我的 → 预设食物」设置手边常备食材，建议更贴合实际")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
    }

    @ViewBuilder
    private var timelineSection: some View {
        if viewModel.timeline.isEmpty {
            Text("还没有记录，点右上角 + 开始打卡")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.timeline) { entry in
                timelineRow(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(entry: entry) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack {
            Text(entry.meal)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignTokens.primary.opacity(0.15))
                .clipShape(Capsule())
            Image(systemName: entry.icon)
                .foregroundStyle(DesignTokens.primary)
                .frame(width: 24)
            Text(entry.titleText)
                .font(.callout)
            if entry.isAIEstimated {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.aiAmber)
                    .accessibilityLabel("AI 估算")
            }
            Spacer()
            Text(Formatting.timeText(entry.createdAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            if let kcalText = entry.kcalText {
                Text("\(kcalText) kcal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
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

- [ ] **Step 4: 运行确认通过**

Run:
```bash
xcodebuild test -project LightCal.xcodeproj -scheme LightCal \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LightCalUITests/TodayFlowUITests 2>&1 | tee /tmp/lightcal-todayui.log
```
Expected: PASS——`testWaterQuickAddAndTextLogging`（Task 1 入库后「133 kcal」真实命中）与新增 `testTimelineShowsWaterAndSwipeDelete` 均通过。若左滑后「删除」按钮找不到，检查 swipeActions 的 Label 文案是否被本地化为其他文字（预期「删除」）；若删除后时间线仍显示旧行，检查 `viewModel.delete` 内 `await refresh()` 是否执行（timeline 变化应触发重渲染）。

- [ ] **Step 5: Commit**

```bash
git add LightCal/UI/Today/TodayDashboardView.swift LightCal/UI/Logging/EntryPointSheet.swift LightCal/UI/Logging/ConfirmCardView.swift LightCalUITests/TodayFlowUITests.swift
git commit -m "feat: 今日页 List 化+时间线饮水混排+左滑删除（含录入 sheet 竞态修复）"
```

---

---

### Task 7: 全量回归 + README 更新

**Files:**
- Modify: `README.md`
- Test: 全量（单测 + UI 测试）

**Interfaces:**
- Consumes: Task 1–6 全部产物
- Produces: 全绿回归 + README 状态更新，本计划完成。

- [ ] **Step 1: 全量单元测试**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalTests 2>&1 | tee /tmp/lightcal-final-unit.log`
Expected: 全绿，测试总数 ≥ 基线（Task 0 记录值）+ 新增用例数。

- [ ] **Step 2: 全量 UI 测试**

Run: `xcodebuild test -project LightCal.xcodeproj -scheme LightCal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LightCalUITests 2>&1 | tee /tmp/lightcal-final-ui.log`
Expected: 全绿（含 OnboardingFlowUITests——本次未动建档流程，必须仍绿）。

- [ ] **Step 3: 更新 README**

把 README.md 第 7 行状态段更新为：

```markdown
- **状态**：v1 实现完成 + 今日记录增强（饮水时间线、左滑删除、肉类细分食物库、图标完善），全量单测 + UI 测试全绿，待真机手工验证
```

并在「文档」列表追加一行：

```markdown
- 今日记录增强设计：[docs/superpowers/specs/2026-08-21-today-log-improvements-design.md](docs/superpowers/specs/2026-08-21-today-log-improvements-design.md)
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README 状态更新（今日记录增强完成）"
```

- [ ] **Step 5: 最终核对**

对照 spec 逐条自查：
1. 饮水列入今日记录 ✓（Task 5/6）
2. 今日记录删除（左滑，食物+饮水）✓（Task 3/5/6）
3. 肉类细分 + 全麦面包（232 条）✓（Task 1）
4. 图标修复与扩充 ✓（Task 2）
5. 全部测试绿 ✓（本任务 Step 1/2）

---
