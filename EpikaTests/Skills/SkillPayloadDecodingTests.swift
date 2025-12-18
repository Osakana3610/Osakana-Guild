import XCTest
@testable import Epika

@MainActor
final class SkillPayloadDecodingTests: XCTestCase {
    func testAllSQLiteSkillPayloadsDecode() async throws {
        let manager = SQLiteMasterDataManager()
        let cache = try await MasterDataLoader.load(manager: manager)
        let skills = cache.allSkills

        var failures: [String] = []
        var samples: [String] = []
        for skill in skills {
            for effect in skill.effects {
                guard !effect.payloadJSON.isEmpty else { continue }
                do {
                    _ = try SkillEffectPayloadDecoder.decode(effect: effect, fallbackEffectType: effect.kind)
                } catch {
                    let message = "\(skill.id)#\(effect.index): \(error)"
                    failures.append(message)
                    if samples.count < 10 {
                        samples.append(message)
                    }
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("Payload decode failures (\(failures.count)):\n" + samples.joined(separator: "\n"))
        }
    }
}
