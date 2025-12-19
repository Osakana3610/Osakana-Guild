import XCTest
@testable import Epika

@MainActor
final class SkillPayloadDecodingTests: XCTestCase {
    func testAllSQLiteSkillEffectsAreValid() async throws {
        let manager = SQLiteMasterDataManager()
        let cache = try await MasterDataLoader.load(manager: manager)
        let skills = cache.allSkills

        var failures: [String] = []
        var samples: [String] = []
        for skill in skills {
            for effect in skill.effects {
                do {
                    let payload = try SkillRuntimeEffectCompiler.decodePayload(from: effect, skillId: skill.id)
                    try SkillRuntimeEffectCompiler.validatePayload(payload, skillId: skill.id, effectIndex: effect.index)
                } catch {
                    let message = "\(skill.id)#\(effect.index) (\(effect.effectType.identifier)): \(error)"
                    failures.append(message)
                    if samples.count < 10 {
                        samples.append(message)
                    }
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("Skill effect validation failures (\(failures.count)):\n" + samples.joined(separator: "\n"))
        }
    }

    func testAllSkillEffectTypesAreRegistered() async throws {
        let manager = SQLiteMasterDataManager()
        let cache = try await MasterDataLoader.load(manager: manager)
        let skills = cache.allSkills

        var unregisteredTypes: Set<String> = []
        for skill in skills {
            for effect in skill.effects {
                if SkillEffectHandlerRegistry.handler(for: effect.effectType) == nil {
                    unregisteredTypes.insert(effect.effectType.identifier)
                }
            }
        }

        if !unregisteredTypes.isEmpty {
            XCTFail("Unregistered effect types: \(unregisteredTypes.sorted().joined(separator: ", "))")
        }
    }
}
