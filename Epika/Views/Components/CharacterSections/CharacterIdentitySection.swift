import SwiftUI

/// キャラクターのプロフィール情報（種族、職業、性別）を表示するセクション
/// CharacterSectionType: race, job
/// subJobは将来実装予定
@MainActor
struct CharacterIdentitySection: View {
    let character: RuntimeCharacter

    var body: some View {
        GroupBox("プロフィール") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("種族", value: character.raceName)
                LabeledContent("職業", value: character.jobName)
                LabeledContent("性別", value: character.race?.gender ?? "不明")
            }
        }
    }
}
