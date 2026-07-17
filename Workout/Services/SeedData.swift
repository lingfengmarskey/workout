import Foundation
import SwiftData

@MainActor
enum SeedData {
    private struct MealTemplate {
        let breakfast: String
        let lunch: String
        let dinner: String
        let snack: String
        let calories: Int
        let protein: Int
    }

    static func seedIfNeeded(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<WeightLossPlan>()
        descriptor.fetchLimit = 1

        guard try context.fetch(descriptor).isEmpty else { return }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: .now)
        let plan = WeightLossPlan(
            name: "我的第一个 8 周减脂计划",
            startDate: startDate,
            durationDays: 56,
            startWeight: 97,
            phaseTargetWeight: 88.5,
            finalTargetWeight: 80,
            dailyCalorieTarget: 1900,
            dailyProteinTarget: 140,
            dailyWaterTarget: 2.3
        )
        try create(plan: plan, in: context)
        CurrentPlanSelection.select(plan)
    }

    static func create(plan: WeightLossPlan, in context: ModelContext) throws {
        context.insert(plan)

        let meals = mealTemplates
        for day in 0..<plan.durationDays {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: plan.startDate) else { continue }
            let meal = meals[day % meals.count]

            context.insert(DailyBodyRecord(planID: plan.id, date: date))
            context.insert(
                DailyMealPlan(
                    planID: plan.id,
                    date: date,
                    breakfast: meal.breakfast,
                    lunch: meal.lunch,
                    dinner: meal.dinner,
                    snack: meal.snack,
                    plannedCalories: meal.calories,
                    plannedProtein: meal.protein,
                    waterTarget: plan.dailyWaterTarget
                )
            )
            context.insert(makeWorkout(planID: plan.id, date: date, dayIndex: day))
        }

        try context.save()
    }

    private static let mealTemplates: [MealTemplate] = [
        .init(
            breakfast: "鸡蛋 2 个＋纳豆 45g＋熟米饭 120g＋菠菜 100g＋无糖豆浆 200ml",
            lunch: "鸡胸肉 200g＋熟米饭 150g＋西兰花 200g＋橄榄油 5g＋豆腐味噌汤",
            dinner: "三文鱼 160g＋熟红薯 180g＋卷心菜 250g＋豆腐 100g",
            snack: "无糖希腊酸奶 200g＋蓝莓 100g",
            calories: 1930,
            protein: 157
        ),
        .init(
            breakfast: "燕麦 50g＋低脂牛奶 250ml＋无糖希腊酸奶 150g＋香蕉 100g＋乳清蛋白 20g",
            lunch: "瘦牛肉 180g＋熟米饭 150g＋彩椒洋葱 250g＋食用油 5g",
            dinner: "鳕鱼 220g＋熟土豆 250g＋蘑菇 200g＋毛豆 100g",
            snack: "苹果 180g＋杏仁 15g",
            calories: 1950,
            protein: 146
        ),
        .init(
            breakfast: "全麦面包 100g＋鸡蛋 2 个＋水浸金枪鱼 70g＋番茄 150g＋无糖酸奶 100g",
            lunch: "猪里脊 200g＋熟米饭 150g＋卷心菜 250g＋泡菜 50g",
            dinner: "虾仁 200g＋熟荞麦面 200g＋豆腐 150g＋青菜 200g",
            snack: "无糖豆浆 200ml＋猕猴桃 2 个",
            calories: 1930,
            protein: 152
        ),
        .init(
            breakfast: "熟米饭 100g＋烤三文鱼 80g＋鸡蛋 1 个＋纳豆 45g＋味噌汤",
            lunch: "去皮鸡腿肉 200g＋熟米饭 150g＋南瓜 150g＋沙拉 200g＋橄榄油 5g",
            dinner: "瘦牛肉 180g＋豆腐 150g＋白菜 300g＋魔芋丝 200g",
            snack: "无糖希腊酸奶 200g＋草莓 150g",
            calories: 1930,
            protein: 150
        ),
        .init(
            breakfast: "燕麦 40g＋无糖豆浆 250ml＋鸡蛋 2 个＋苹果 100g＋花生酱 10g",
            lunch: "烤青花鱼 150g＋熟米饭 150g＋萝卜 150g＋菠菜 150g",
            dinner: "鸡胸肉 200g＋意面干重 70g＋番茄酱 150g＋蘑菇和沙拉",
            snack: "低脂茅屋奶酪 150g＋橙子 150g",
            calories: 2000,
            protein: 153
        ),
        .init(
            breakfast: "无糖希腊酸奶 250g＋低糖麦片 40g＋香蕉 100g＋水煮蛋 2 个",
            lunch: "金枪鱼刺身 180g＋熟米饭 180g＋牛油果 50g＋黄瓜和海苔",
            dinner: "猪里脊 180g＋熟红薯 200g＋西兰花 200g＋豆腐 100g",
            snack: "低脂牛奶 250ml＋杏仁 10g",
            calories: 1950,
            protein: 146
        ),
        .init(
            breakfast: "全麦吐司 80g＋低脂茅屋奶酪 150g＋鸡蛋 1 个＋猕猴桃＋低脂牛奶",
            lunch: "低油鸡肉咖喱：鸡胸肉 200g＋熟米饭 150g＋洋葱胡萝卜 250g",
            dinner: "烤鳕鱼 200g＋熟米饭 100g＋毛豆 100g＋混合蔬菜 250g",
            snack: "无糖酸奶 150g＋梨 150g",
            calories: 1920,
            protein: 160
        )
    ]

    private static func makeWorkout(planID: UUID, date: Date, dayIndex: Int) -> DailyWorkoutPlan {
        let week = dayIndex / 7
        let weekday = dayIndex % 7
        let stepTargets = [7_000, 8_000, 9_000, 9_500, 10_000, 10_500, 11_000, 11_000]
        let cardioMinutes = [35, 40, 45, 45, 50, 50, 55, 60]
        let steps = stepTargets[min(week, stepTargets.count - 1)]
        let cardio = cardioMinutes[min(week, cardioMinutes.count - 1)]
        let warmup = "原地走 2 分钟＋肩、髋、踝活动，共 5 分钟"
        let cooldown = "小腿、腿后侧、臀部、胸背拉伸 5～8 分钟"

        switch weekday {
        case 0:
            return .init(
                planID: planID,
                date: date,
                workoutType: "力量 A",
                strengthDescription: "椅子深蹲 3×10～12；桌边俯卧撑 3×10～12；背包划船 3×10～12；臀桥 3×15；平板支撑 3×30 秒",
                cardioDescription: "训练后轻松走 10 分钟",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: 45,
                targetSteps: steps,
                intensityDescription: "RPE 6～7，每组保留 2～3 次余力"
            )
        case 1:
            return .init(
                planID: planID,
                date: date,
                workoutType: "快走",
                strengthDescription: "无",
                cardioDescription: "连续快走 \(cardio) 分钟，可拆成早晚两次",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: cardio + 10,
                targetSteps: steps + 500,
                intensityDescription: "能说短句，但不能轻松唱歌"
            )
        case 2:
            return .init(
                planID: planID,
                date: date,
                workoutType: "力量 B",
                strengthDescription: "背包硬拉 3×10～12；扶墙后撤弓步 3×8/侧；背包推举 3×10～12；鸟狗 3×10/侧；侧平板 3×20 秒/侧",
                cardioDescription: "训练后轻松走 10 分钟",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: 45,
                targetSteps: steps,
                intensityDescription: "动作标准优先，膝盖方向与脚尖一致"
            )
        case 3:
            return .init(
                planID: planID,
                date: date,
                workoutType: "主动恢复",
                strengthDescription: "无",
                cardioDescription: "轻松散步 30 分钟",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: 40,
                targetSteps: steps,
                intensityDescription: "RPE 3～4，以恢复为主"
            )
        case 4:
            return .init(
                planID: planID,
                date: date,
                workoutType: "力量 C",
                strengthDescription: "台阶踏步 3×10/侧；斜板俯卧撑 3×10～12；背包划船 3×12；臀推 3×15；死虫 3×10/侧",
                cardioDescription: "训练后轻松走 10 分钟",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: 45,
                targetSteps: steps + 500,
                intensityDescription: "动作标准后再增加背包重量"
            )
        case 5:
            return .init(
                planID: planID,
                date: date,
                workoutType: "中等有氧",
                strengthDescription: "无",
                cardioDescription: "骑车、游泳或快走任选一种，持续 \(cardio + 10) 分钟",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: cardio + 20,
                targetSteps: steps + 1_000,
                intensityDescription: "RPE 5～6，不冲刺"
            )
        default:
            return .init(
                planID: planID,
                date: date,
                workoutType: "长距离低强度",
                strengthDescription: "无",
                cardioDescription: "户外快走或骑车 \(cardio + 20) 分钟，可分两次完成",
                warmupDescription: warmup,
                cooldownDescription: cooldown,
                plannedDurationMinutes: cardio + 30,
                targetSteps: steps + 1_000,
                intensityDescription: "全程呼吸可控，结束后不应精疲力尽"
            )
        }
    }
}
