// ==============================================================================
// SkillModifierSummary.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 補正一覧の集計結果（表示用データ）を保持する
//
// ==============================================================================

import Foundation

struct SkillModifierSummary: Sendable, Hashable {
    struct Entry: Sendable, Hashable {
        let key: SkillModifierKey
        let value: SkillModifierValue?
        let conditional: Bool

        nonisolated init(key: SkillModifierKey, value: SkillModifierValue?, conditional: Bool) {
            self.key = key
            self.value = value
            self.conditional = conditional
        }
    }

    enum SkillModifierValue: Sendable, Hashable {
        case percent(Double)
        case multiplier(Double)
        case additive(Double)
        case count(Int)
        case flag
    }

    let entries: [Entry]

    nonisolated init(entries: [Entry]) {
        self.entries = entries
    }

    nonisolated var isEmpty: Bool {
        entries.isEmpty
    }

    nonisolated static let empty = SkillModifierSummary(entries: [])
}

extension SkillModifierSummary {
    nonisolated static func build(
        snapshot: SkillModifierSnapshot,
        dynamicKeys: Set<SkillModifierKey>
    ) -> SkillModifierSummary {
        var entries: [SkillModifierKey: Entry] = [:]

        func addStatic(_ key: SkillModifierKey, value: SkillModifierValue) {
            guard !dynamicKeys.contains(key) else { return }
            entries[key] = Entry(key: key, value: value, conditional: false)
        }

        func addDynamic(_ key: SkillModifierKey) {
            guard entries[key] == nil else { return }
            entries[key] = Entry(key: key, value: nil, conditional: true)
        }

        for (key, value) in snapshot.additivePercents {
            addStatic(key, value: .percent(value))
        }

        for (key, value) in snapshot.additiveValues {
            if key.kind == .attackCountAdditive {
                addStatic(key, value: .count(Int(value.rounded(.towardZero))))
            } else {
                addStatic(key, value: .additive(value))
            }
        }

        for (key, value) in snapshot.multipliers {
            addStatic(key, value: .multiplier(value))
        }

        for (key, value) in snapshot.maxValues {
            addStatic(key, value: .percent(value))
        }

        for (key, value) in snapshot.minValues {
            if key.kind == .minHitScale {
                addStatic(key, value: .multiplier(value))
            } else if key.kind == .retreatAtTurn && key.slot == 0 {
                addStatic(key, value: .count(Int(value.rounded(.towardZero))))
            } else {
                addStatic(key, value: .percent(value))
            }
        }

        for (key, value) in snapshot.intValues {
            addStatic(key, value: .count(value))
        }

        for key in snapshot.flags {
            addStatic(key, value: .flag)
        }

        for key in dynamicKeys {
            addDynamic(key)
        }

        let sorted = entries.values.sorted { $0.key.rawValue < $1.key.rawValue }
        return SkillModifierSummary(entries: sorted)
    }
}
