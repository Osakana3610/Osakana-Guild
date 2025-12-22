// ==============================================================================
// CharacterIdentitySection.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターのプロフィール情報（種族、職業、性別）を表示
//   - 読み取り専用の基本情報セクション
//
// 【View構成】
//   - LabeledContent × 3
//     - 種族名
//     - 職業名
//     - 性別（race.genderDisplayName）
//   - subJobは将来実装予定（現在は未使用）
//
// 【使用箇所】
//   - キャラクター詳細画面（CharacterSectionType.race, job）
//
// ==============================================================================

import SwiftUI

/// キャラクターのプロフィール情報（種族、職業、性別）を表示するセクション
/// CharacterSectionType: race, job
/// subJobは将来実装予定
@MainActor
struct CharacterIdentitySection: View {
    let character: RuntimeCharacter
    @State private var showRaceDetail = false
    @State private var selectedJob: JobDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("種族") {
                Text(character.raceName)
                    .onTapGesture { showRaceDetail = true }
            }
            if let currentJob = character.job {
                LabeledContent("職業") {
                    Text(currentJob.name)
                        .onTapGesture { selectedJob = currentJob }
                }
                if let previousJob = character.previousJob {
                    LabeledContent("前職") {
                        Text(previousJob.name)
                            .onTapGesture { selectedJob = previousJob }
                    }
                }
            } else {
                LabeledContent("職業", value: character.jobName)
            }
            LabeledContent("性別", value: character.race?.genderDisplayName ?? "不明")
        }
        .sheet(isPresented: $showRaceDetail) {
            if let race = character.race {
                RaceDetailSheet(race: race)
            }
        }
        .sheet(item: $selectedJob) { job in
            JobDetailSheet(job: job, genderCode: character.race?.genderCode)
        }
    }
}
