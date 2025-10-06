import Foundation

struct ExplorationEventScheduler {
    enum Category: Sendable {
        case nothing
        case scripted
        case combat
    }

    private struct WeightConfig {
        let nothing: Double
        let scripted: Double
        let combat: Double
    }

    private let weights: WeightConfig

    init(nothing: Double = 0.6,
         scripted: Double = 0.1,
         combat: Double = 0.3) {
        self.weights = WeightConfig(nothing: nothing,
                                    scripted: scripted,
                                    combat: combat)
    }

    func nextCategory(hasScriptedEvents: Bool,
                      hasCombatEvents: Bool,
                      random: inout GameRandomSource) throws -> Category {
        var entries: [(Category, Double)] = []
        entries.append((.nothing, max(0, weights.nothing)))
        entries.append((.scripted, hasScriptedEvents ? max(0, weights.scripted) : 0))
        entries.append((.combat, hasCombatEvents ? max(0, weights.combat) : 0))

        let total = entries.reduce(0.0) { $0 + $1.1 }
        guard total > 0 else {
            throw RuntimeError.invalidConfiguration(reason: "探索イベントカテゴリの重みが全て0です")
        }

        let pick = random.nextDouble() * total
        var cursor: Double = 0
        for (category, weight) in entries {
            guard weight > 0 else { continue }
            cursor += weight
            if pick <= cursor {
                return category
            }
        }
        return .nothing
    }
}
