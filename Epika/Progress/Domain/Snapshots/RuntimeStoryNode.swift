import Foundation

struct RuntimeStoryNode: Identifiable, Hashable, Sendable {
    let definition: StoryNodeDefinition
    let isUnlocked: Bool
    let isCompleted: Bool
    let isRewardClaimed: Bool

    var id: UInt16 { definition.id }
    var title: String { definition.title }
    var content: String { definition.content }
    var chapterId: String { String(definition.chapter) }
    var section: Int { definition.section }

    var unlockRequirements: [UnlockCondition] {
        definition.unlockRequirements
    }

    var unlockModules: [StoryModule] {
        definition.unlockModules
    }

    // MARK: - 表示用

    var unlockConditions: [String] {
        definition.unlockRequirements.map { condition in
            switch condition.type {
            case 0: return "ストーリー \(condition.value) を読む"
            case 1: return "ダンジョン \(condition.value) をクリア"
            default: return "条件 \(condition.type):\(condition.value)"
            }
        }
    }

    var unlocksModules: [String] {
        definition.unlockModules.map { module in
            switch module.type {
            case 0: return "ダンジョン \(module.value)"
            default: return "コンテンツ \(module.type):\(module.value)"
            }
        }
    }

    var rewardSummary: String {
        if definition.rewards.isEmpty { return "" }
        return definition.rewards.map { reward in
            switch reward.type {
            case 0: return "金貨 \(reward.value)"
            case 1: return "経験値 \(reward.value)"
            default: return "\(reward.type):\(reward.value)"
            }
        }.joined(separator: ", ")
    }

    var canRead: Bool { isUnlocked && !isCompleted }
}
