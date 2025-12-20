// ==============================================================================
// SkillEffectPayloadSchema.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - スキルペイロードの値部分を型安全に表現する共通スキーマ
//   - 数値・文字列・文字列配列を一括で保持し、柔軟なデコードをサポート
//
// 【データ構造】
//   - SkillEffectPayloadValues: ペイロードの値を保持する構造体
//     - numericValues: 数値パラメータのマップ
//     - stringValues: 文字列パラメータのマップ
//     - stringArrayValues: 文字列配列パラメータのマップ
//   - SkillEffectFlexibleValue: 型が混在する値の柔軟なデコーダ
//
// 【使用箇所】
//   - SkillDefinition.Effect のペイロードデコード
//   - SkillRuntimeEffectCompiler.Validation でのペイロード処理
//
// ==============================================================================

import Foundation

/// スキルペイロードの値部分を型安全に表現する共通スキーマ。
/// 数値・文字列・文字列配列を一括で保持する。
struct SkillEffectPayloadValues: Decodable, Sendable, Hashable {
    let numericValues: [String: Double]
    let stringValues: [String: String]
    let stringArrayValues: [String: [String]]

    init(numericValues: [String: Double],
         stringValues: [String: String],
         stringArrayValues: [String: [String]]) {
        self.numericValues = numericValues
        self.stringValues = stringValues
        self.stringArrayValues = stringArrayValues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: SkillEffectFlexibleValue].self)
        let result = SkillEffectPayloadValues.makeMaps(from: raw,
                                                       stringValues: [:],
                                                       stringArrayValues: [:])
        self = SkillEffectPayloadValues(numericValues: result.numericValues,
                                        stringValues: result.stringValues,
                                        stringArrayValues: result.stringArrayValues)
    }

    static func from(rawValues: [String: SkillEffectFlexibleValue]?,
                     stringValues: [String: String]?,
                     stringArrayValues: [String: [String]]?) -> SkillEffectPayloadValues {
        let raw = rawValues ?? [:]
        return SkillEffectPayloadValues.makeMaps(from: raw,
                                                 stringValues: stringValues ?? [:],
                                                 stringArrayValues: stringArrayValues ?? [:])
    }

    private static func makeMaps(from raw: [String: SkillEffectFlexibleValue],
                                 stringValues: [String: String],
                                 stringArrayValues: [String: [String]]) -> SkillEffectPayloadValues {
        var numeric: [String: Double] = [:]
        var strings: [String: String] = stringValues
        var stringArrays: [String: [String]] = stringArrayValues

        for (key, value) in raw {
            if let number = value.doubleValue {
                numeric[key] = number
                continue
            }
            if let array = value.stringArrayValue {
                stringArrays[key] = array
                continue
            }
            if let string = value.stringValue {
                strings[key] = string
            }
        }

        return SkillEffectPayloadValues(numericValues: numeric,
                                        stringValues: strings,
                                        stringArrayValues: stringArrays)
    }

    static let empty = SkillEffectPayloadValues(numericValues: [:],
                                                stringValues: [:],
                                                stringArrayValues: [:])
}

/// `value` 内で値の型が混在する場合の柔軟なデコーダ。
struct SkillEffectFlexibleValue: Decodable, Sendable, Hashable {
    let doubleValue: Double?
    let stringValue: String?
    let stringArrayValue: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            doubleValue = double
            stringValue = nil
            stringArrayValue = nil
            return
        }
        if let array = try? container.decode([String].self) {
            doubleValue = nil
            stringValue = nil
            stringArrayValue = array
            return
        }
        if let string = try? container.decode(String.self) {
            doubleValue = nil
            stringValue = string
            stringArrayValue = nil
            return
        }
        doubleValue = nil
        stringValue = nil
        stringArrayValue = nil
    }
}
