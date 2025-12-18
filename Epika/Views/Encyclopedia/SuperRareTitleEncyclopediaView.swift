import SwiftUI

struct SuperRareTitleEncyclopediaView: View {
    @Environment(AppServices.self) private var appServices
    @State private var titles: [SuperRareTitleDefinition] = []
    @State private var skillDefinitions: [UInt16: SkillDefinition] = [:]
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else {
                List {
                    ForEach(titles) { title in
                        SuperRareTitleRow(title: title, skillDefinitions: skillDefinitions)
                    }
                }
            }
        }
        .navigationTitle("超レア図鑑")
        .avoidBottomGameInfo()
        .task { await loadData() }
    }

    private func loadData() async {
        let masterData = appServices.masterDataCache
        titles = masterData.allSuperRareTitles
        skillDefinitions = Dictionary(uniqueKeysWithValues: masterData.allSkills.map { ($0.id, $0) })
        isLoading = false
    }
}

private struct SuperRareTitleRow: View {
    let title: SuperRareTitleDefinition
    let skillDefinitions: [UInt16: SkillDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No.\(title.id)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(title.name)
                .font(.headline)

            if !title.skillIds.isEmpty {
                ForEach(title.skillIds, id: \.self) { skillId in
                    if let skill = skillDefinitions[skillId] {
                        Text(skill.name)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
