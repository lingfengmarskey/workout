# Workout · 减脂计划

一个面向个人使用的 iOS 减脂计划与执行记录 App。

首个版本聚焦一个简单闭环：

> 制定计划 → 查看今日任务 → 记录体重与体型 → 完成饮食 → 完成锻炼 → 每周复盘

## 当前范围

- 每日体重、腰围、睡眠与体型照片记录
- 每日早餐、午餐、晚餐和加餐计划
- 每日力量、有氧、步数与训练时长计划
- 计划体重、实际体重和 7 日平均趋势
- 每周饮食与锻炼执行率复盘
- 本地优先，后续可接入 iCloud 与 HealthKit

## 技术栈

- SwiftUI
- SwiftData
- Charts
- PhotosPicker
- iOS 17+
- XcodeGen（生成 Xcode 工程）

## 本地运行

```bash
brew install xcodegen
xcodegen generate
open Workout.xcodeproj
```

在 Xcode 中选择 `Workout` Scheme 和任意 iOS 17+ 模拟器运行。

## 仓库结构

```text
Workout/
  App/                 App 入口与主导航
  Models/              SwiftData 数据模型
  Features/            今日、体重、饮食、锻炼、进度、设置
  Services/            默认计划与数据生成
  Shared/              通用组件和工具
docs/
  MVP-PRD.md           MVP 产品需求文档
  ROADMAP.md           开发路线与阶段目标
project.yml            XcodeGen 工程定义
```

## 开发原则

1. 首版只解决个人每天坚持记录的问题。
2. 核心操作尽量在 2 分钟内完成。
3. 数据默认仅保存在本地设备。
4. 优先关注 7 日平均和长期趋势，而非单日体重波动。
5. 在连续使用两周前，不增加社交、AI 识别、订阅等复杂功能。

## 文档

- [MVP 产品需求文档](docs/MVP-PRD.md)
- [开发路线](docs/ROADMAP.md)

## 状态

当前为项目初始化阶段。已包含可生成的 SwiftUI/SwiftData App 骨架，后续功能开发继续在本仓库进行。
