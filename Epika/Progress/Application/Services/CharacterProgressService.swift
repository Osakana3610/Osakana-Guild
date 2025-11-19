import Foundation
import SwiftData

actor CharacterProgressService {
    struct CharacterCreationRequest: Sendable {
        var displayName: String
        var raceId: String
        var gender: String
        var jobId: String
    }

    struct BattleResultUpdate: Sendable {
        let characterId: UUID
        let experienceDelta: Int
        let totalBattlesDelta: Int
        let victoriesDelta: Int
        let defeatsDelta: Int
    }

    private let container: ModelContainer
    private let runtime: ProgressRuntimeService
    private var raceLevelCache: [String: Int] = [:]
    private var raceMaxExperienceCache: [String: Int] = [:]

    init(container: ModelContainer, runtime: ProgressRuntimeService) {
        self.container = container
        self.runtime = runtime
    }

    private func notifyCharacterProgressDidChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .characterProgressDidChange, object: nil)
        }
    }

    func allCharacters() async throws -> [CharacterSnapshot] {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>()
        descriptor.sortBy = [SortDescriptor(\CharacterRecord.createdAt, order: .forward)]
        let records = try context.fetch(descriptor)
        return try await makeSnapshots(records, context: context)
    }

    func character(withId id: UUID) async throws -> CharacterSnapshot? {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        return try await makeSnapshot(record, context: context)
    }

    func characters(withIds ids: [UUID]) async throws -> [CharacterSnapshot] {
        guard !ids.isEmpty else { return [] }
        let context = makeContext()
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { ids.contains($0.id) })
        let records = try context.fetch(descriptor)
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var ordered: [CharacterRecord] = []
        var missing: [UUID] = []
        var seen: Set<UUID> = []
        for id in ids {
            guard let record = map[id] else {
                missing.append(id)
                continue
            }
            if seen.insert(id).inserted {
                ordered.append(record)
            }
        }
        if !missing.isEmpty {
            let identifierList = missing.map { $0.uuidString }.joined(separator: ", ")
            throw ProgressError.invalidInput(description: "キャラクターが見つかりません (ID: \(identifierList))")
        }
        return try await makeSnapshots(ordered, context: context)
    }

    func runtimeCharacter(from snapshot: CharacterSnapshot) async throws -> RuntimeCharacter {
        try await runtime.runtimeCharacter(from: snapshot)
    }

    func createCharacter(_ request: CharacterCreationRequest) async throws -> CharacterSnapshot {
        let trimmedName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProgressError.invalidInput(description: "キャラクター名を入力してください")
        }
        let context = makeContext()
        let now = Date()
        let gender = CharacterGender(rawValue: request.gender) ?? .other
        let avatarIdentifier = try await resolveAvatarIdentifier(jobId: request.jobId,
                                                                   gender: gender)
        let record = CharacterRecord(displayName: trimmedName,
                                     raceId: request.raceId,
                                     gender: gender,
                                     jobId: request.jobId,
                                     avatarIdentifier: avatarIdentifier,
                                     level: 1,
                                     experience: 0,
                                     strength: 10,
                                     wisdom: 10,
                                     spirit: 10,
                                     vitality: 10,
                                     agility: 10,
                                     luck: 10,
                                     currentHP: 100,
                                     maximumHP: 100,
                                     physicalAttack: 0,
                                     magicalAttack: 0,
                                     physicalDefense: 0,
                                     magicalDefense: 0,
                                     hitRate: 0,
                                     evasionRate: 0,
                                     criticalRate: 0,
                                     attackCount: 1,
                                     magicalHealing: 0,
                                     trapRemoval: 0,
                                     additionalDamage: 0,
                                     breathDamage: 0,
                                     primaryPersonalityId: nil,
                                     secondaryPersonalityId: nil,
                                     totalBattles: 0,
                                     totalVictories: 0,
                                     defeatCount: 0,
                                     createdAt: now,
                                     updatedAt: now)
        context.insert(record)
        try context.save()
        notifyCharacterProgressDidChange()
        return try await makeSnapshot(record, context: context)
    }

    func updateCharacter(id: UUID,
                         mutate: @Sendable (inout CharacterSnapshot) throws -> Void) async throws -> CharacterSnapshot {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw ProgressError.characterNotFound
        }
        var snapshot = try await makeSnapshot(record, context: context)
        try mutate(&snapshot)
        if snapshot.experience < 0 {
            throw ProgressError.invalidInput(description: "経験値は0以上である必要があります")
        }
        let clampedExperience = try await clampExperience(snapshot.experience, raceId: snapshot.raceId)
        snapshot.experience = clampedExperience
        let normalizedLevel = try await resolveLevel(for: clampedExperience, raceId: snapshot.raceId)
        snapshot.level = normalizedLevel
        let timestamp = Date()
        record.needsCombatRecalculation = true
        apply(snapshot: snapshot, to: record, timestamp: timestamp)
        try replaceAssociations(from: snapshot, context: context, timestamp: timestamp)
        record.updatedAt = timestamp
        try context.save()
        notifyCharacterProgressDidChange()
        return try await makeSnapshot(record, context: context)
    }

    func applyBattleResults(_ updates: [BattleResultUpdate]) async throws {
        guard !updates.isEmpty else { return }
        let context = makeContext()
        let ids = updates.map { $0.characterId }
        let descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { ids.contains($0.id) })
        let records = try context.fetch(descriptor)
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let timestamp = Date()
        for update in updates {
            guard let record = map[update.characterId] else {
                throw ProgressError.characterNotFound
            }
            if update.experienceDelta != 0 {
                let previousLevel = record.level
                let addition = record.experience.addingReportingOverflow(update.experienceDelta)
                guard !addition.overflow else {
                    throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
                }
                let updatedExperience = max(0, addition.partialValue)
                let cappedExperience = try await clampExperience(updatedExperience, raceId: record.raceId)
                record.experience = cappedExperience
                let computedLevel = try await resolveLevel(for: cappedExperience, raceId: record.raceId)
                if computedLevel != previousLevel {
                    record.level = computedLevel
                    record.needsCombatRecalculation = true
                }
            }
            if update.totalBattlesDelta != 0 {
                record.totalBattles = max(0, record.totalBattles &+ update.totalBattlesDelta)
            }
            if update.victoriesDelta != 0 {
                record.totalVictories = max(0, record.totalVictories &+ update.victoriesDelta)
            }
            if update.defeatsDelta != 0 {
                record.defeatCount = max(0, record.defeatCount &+ update.defeatsDelta)
            }
            record.updatedAt = timestamp
        }
        try context.save()
        notifyCharacterProgressDidChange()
    }

    func deleteCharacter(id: UUID) async throws {
        let context = makeContext()
        var descriptor = FetchDescriptor<CharacterRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        try deleteAssociations(for: id, context: context)
        try removeFromParties(characterId: id, context: context)
        context.delete(record)
        try context.save()
        notifyCharacterProgressDidChange()
    }
}

private extension CharacterProgressService {
    func resolveLevel(for experience: Int, raceId: String) async throws -> Int {
        let maxLevel = try await raceMaxLevel(for: raceId)
        do {
            return try await MainActor.run {
                try CharacterExperienceTable.level(forTotalExperience: experience, maximumLevel: maxLevel)
            }
        } catch CharacterExperienceError.invalidLevel {
            throw ProgressError.invalidInput(description: "経験値テーブルに無効なレベル要求が行われました")
        } catch CharacterExperienceError.invalidExperience {
            throw ProgressError.invalidInput(description: "経験値が負の値になる操作は許可されていません")
        } catch CharacterExperienceError.overflowedComputation {
            throw ProgressError.invalidInput(description: "経験値計算中にオーバーフローが発生しました")
        }
    }

    func raceMaxLevel(for raceId: String) async throws -> Int {
        if let cached = raceLevelCache[raceId] {
            return cached
        }
        let resolved = try await runtime.raceMaxLevel(for: raceId)
        raceLevelCache[raceId] = resolved
        return resolved
    }

    func clampExperience(_ experience: Int, raceId: String) async throws -> Int {
        guard experience > 0 else { return 0 }
        let maximum = try await raceMaxExperience(for: raceId)
        return min(experience, maximum)
    }

    func raceMaxExperience(for raceId: String) async throws -> Int {
        if let cached = raceMaxExperienceCache[raceId] {
            return cached
        }
        let maxLevel = try await raceMaxLevel(for: raceId)
        let maximumExperience = try await MainActor.run {
            try CharacterExperienceTable.totalExperience(toReach: maxLevel)
        }
        raceMaxExperienceCache[raceId] = maximumExperience
        return maximumExperience
    }

    func resolveAvatarIdentifier(jobId: String, gender: CharacterGender) async throws -> String {
        try await resolveAvatarIdentifier(jobId: jobId, genderRawValue: gender.rawValue)
    }

    func resolveAvatarIdentifier(jobId: String, genderRawValue: String) async throws -> String {
        do {
            return try await MainActor.run {
                try CharacterAvatarIdentifierResolver.defaultAvatarIdentifier(jobId: jobId,
                                                                              genderRawValue: genderRawValue)
            }
        } catch let resolverError as CharacterAvatarIdentifierResolverError {
            let message = resolverError.errorDescription ?? resolverError.localizedDescription
            throw ProgressError.invalidInput(description: message)
        } catch {
            throw error
        }
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func makeSnapshots(_ records: [CharacterRecord], context: ModelContext) async throws -> [CharacterSnapshot] {
        var snapshots: [CharacterSnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            let snapshot = try await makeSnapshot(record, context: context)
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func makeSnapshot(_ record: CharacterRecord, context: ModelContext) async throws -> CharacterSnapshot {
        let characterId = record.id
        let skills = try context.fetch(FetchDescriptor<CharacterSkillRecord>(predicate: #Predicate { $0.characterId == characterId }))
        let equipment = try context.fetch(FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId }))
        let jobs = try context.fetch(FetchDescriptor<CharacterJobHistoryRecord>(predicate: #Predicate { $0.characterId == characterId }))
        let tags = try context.fetch(FetchDescriptor<CharacterExplorationTagRecord>(predicate: #Predicate { $0.characterId == characterId }))
        return try await snapshot(from: record,
                                  skills: skills,
                                  equipment: equipment,
                                  jobs: jobs,
                                  tags: tags,
                                  context: context)
    }

    func snapshot(from record: CharacterRecord,
                  skills: [CharacterSkillRecord],
                  equipment: [CharacterEquipmentRecord],
                  jobs: [CharacterJobHistoryRecord],
                  tags: [CharacterExplorationTagRecord],
                  context: ModelContext) async throws -> CharacterSnapshot {
        let attributes = CharacterSnapshot.CoreAttributes(strength: record.strength,
                                                          wisdom: record.wisdom,
                                                          spirit: record.spirit,
                                                          vitality: record.vitality,
                                                          agility: record.agility,
                                                          luck: record.luck)
        let hitPoints = CharacterSnapshot.HitPoints(current: record.currentHP,
                                                    maximum: record.maximumHP)
        let combat = CharacterSnapshot.Combat(maxHP: record.maximumHP,
                                              physicalAttack: record.physicalAttack,
                                              magicalAttack: record.magicalAttack,
                                              physicalDefense: record.physicalDefense,
                                              magicalDefense: record.magicalDefense,
                                              hitRate: record.hitRate,
                                              evasionRate: record.evasionRate,
                                              criticalRate: record.criticalRate,
                                              attackCount: record.attackCount,
                                              magicalHealing: record.magicalHealing,
                                              trapRemoval: record.trapRemoval,
                                              additionalDamage: record.additionalDamage,
                                              breathDamage: record.breathDamage,
                                              isMartialEligible: record.isMartialEligible)
        let personality = CharacterSnapshot.Personality(primaryId: record.primaryPersonalityId,
                                                         secondaryId: record.secondaryPersonalityId)
        let learnedSkills = skills.map { skill in
            CharacterSnapshot.LearnedSkill(id: skill.id,
                                           skillId: skill.skillId,
                                           level: skill.level,
                                           isEquipped: skill.isEquipped,
                                           createdAt: skill.createdAt,
                                           updatedAt: skill.updatedAt)
        }
        let equippedItems = equipment.map { item in
            CharacterSnapshot.EquippedItem(id: item.id,
                                            itemId: item.itemId,
                                            quantity: item.quantity,
                                            normalTitleId: item.normalTitleId,
                                            superRareTitleId: item.superRareTitleId,
                                            socketKey: item.socketKey,
                                            createdAt: item.createdAt,
                                            updatedAt: item.updatedAt)
        }
        let achievements = CharacterSnapshot.AchievementCounters(totalBattles: record.totalBattles,
                                                                  totalVictories: record.totalVictories,
                                                                  defeatCount: record.defeatCount)
        let jobHistory = jobs.map { history in
            CharacterSnapshot.JobHistoryEntry(id: history.id,
                                               jobId: history.jobId,
                                               achievedAt: history.achievedAt,
                                               createdAt: history.createdAt,
                                               updatedAt: history.updatedAt)
        }
        let explorationTags = Set(tags.map(\.value))
        func clamp(_ value: Int) -> Int {
            max(0, min(100, value))
        }
        let actionPreferences = CharacterSnapshot.ActionPreferences(attack: clamp(record.actionRateAttack),
                                                                     clericMagic: clamp(record.actionRateClericMagic),
                                                                     arcaneMagic: clamp(record.actionRateArcaneMagic),
                                                                     breath: clamp(record.actionRateBreath))

        var avatarIdentifier = record.avatarIdentifier
        if avatarIdentifier.isEmpty {
            let resolvedIdentifier = try await resolveAvatarIdentifier(jobId: record.jobId,
                                                                       genderRawValue: record.genderRawValue)
            avatarIdentifier = resolvedIdentifier
            record.avatarIdentifier = resolvedIdentifier
        }
        var snapshot = CharacterSnapshot(persistentIdentifier: record.persistentModelID,
                                         id: record.id,
                                         displayName: record.displayName,
                                         raceId: record.raceId,
                                         gender: record.genderRawValue,
                                         jobId: record.jobId,
                                         avatarIdentifier: avatarIdentifier,
                                         level: record.level,
                                         experience: record.experience,
                                         attributes: attributes,
                                         hitPoints: hitPoints,
                                         combat: combat,
                                         personality: personality,
                                         learnedSkills: learnedSkills,
                                         equippedItems: equippedItems,
                                         jobHistory: jobHistory,
                                         explorationTags: explorationTags,
                                         achievements: achievements,
                                         actionPreferences: actionPreferences,
                                         createdAt: record.createdAt,
                                         updatedAt: record.updatedAt)

        if record.needsCombatRecalculation {
            let result = try await runtime.recalculateCombatSnapshot(for: snapshot)
            let updatedAttributes = CharacterSnapshot.CoreAttributes(strength: result.attributes.strength,
                                                                      wisdom: result.attributes.wisdom,
                                                                      spirit: result.attributes.spirit,
                                                                      vitality: result.attributes.vitality,
                                                                      agility: result.attributes.agility,
                                                                      luck: result.attributes.luck)
            snapshot.attributes = updatedAttributes
            var updatedHitPoints = CharacterSnapshot.HitPoints(current: result.hitPoints.current,
                                                               maximum: result.hitPoints.maximum)
            let wasFull = snapshot.hitPoints.current >= snapshot.hitPoints.maximum
            if wasFull {
                updatedHitPoints.current = updatedHitPoints.maximum
            } else {
                updatedHitPoints.current = min(snapshot.hitPoints.current, updatedHitPoints.maximum)
            }
            snapshot.hitPoints = updatedHitPoints
            let updatedCombat = CharacterSnapshot.Combat(maxHP: result.combat.maxHP,
                                                         physicalAttack: result.combat.physicalAttack,
                                                         magicalAttack: result.combat.magicalAttack,
                                                         physicalDefense: result.combat.physicalDefense,
                                                         magicalDefense: result.combat.magicalDefense,
                                                         hitRate: result.combat.hitRate,
                                                         evasionRate: result.combat.evasionRate,
                                                         criticalRate: result.combat.criticalRate,
                                                         attackCount: result.combat.attackCount,
                                                         magicalHealing: result.combat.magicalHealing,
                                                         trapRemoval: result.combat.trapRemoval,
                                                         additionalDamage: result.combat.additionalDamage,
                                                         breathDamage: result.combat.breathDamage,
                                                         isMartialEligible: result.combat.isMartialEligible)
            snapshot.combat = updatedCombat

            let timestamp = Date()
            applyRecalculated(result: result,
                              hitPoints: updatedHitPoints,
                              to: record,
                              timestamp: timestamp)
            record.needsCombatRecalculation = false
            snapshot.updatedAt = timestamp

            try context.save()
        }

        return snapshot
    }

    func apply(snapshot: CharacterSnapshot,
               to record: CharacterRecord,
               timestamp: Date) {
        record.needsCombatRecalculation = true
        record.displayName = snapshot.displayName
        record.raceId = snapshot.raceId
        record.genderRawValue = snapshot.gender
        record.jobId = snapshot.jobId
        record.avatarIdentifier = snapshot.avatarIdentifier
        record.level = snapshot.level
        record.experience = snapshot.experience
        record.strength = snapshot.attributes.strength
        record.wisdom = snapshot.attributes.wisdom
        record.spirit = snapshot.attributes.spirit
        record.vitality = snapshot.attributes.vitality
        record.agility = snapshot.attributes.agility
        record.luck = snapshot.attributes.luck
        record.currentHP = snapshot.hitPoints.current
        record.maximumHP = snapshot.hitPoints.maximum
        record.physicalAttack = snapshot.combat.physicalAttack
        record.magicalAttack = snapshot.combat.magicalAttack
        record.physicalDefense = snapshot.combat.physicalDefense
        record.magicalDefense = snapshot.combat.magicalDefense
        record.hitRate = snapshot.combat.hitRate
        record.evasionRate = snapshot.combat.evasionRate
        record.criticalRate = snapshot.combat.criticalRate
        record.attackCount = snapshot.combat.attackCount
        record.isMartialEligible = snapshot.combat.isMartialEligible
        record.actionRateAttack = snapshot.actionPreferences.attack
        record.actionRateClericMagic = snapshot.actionPreferences.clericMagic
        record.actionRateArcaneMagic = snapshot.actionPreferences.arcaneMagic
        record.actionRateBreath = snapshot.actionPreferences.breath
        record.primaryPersonalityId = snapshot.personality.primaryId
        record.secondaryPersonalityId = snapshot.personality.secondaryId
        record.totalBattles = snapshot.achievements.totalBattles
        record.totalVictories = snapshot.achievements.totalVictories
        record.defeatCount = snapshot.achievements.defeatCount
        record.updatedAt = timestamp
    }

    func applyRecalculated(result: CombatStatCalculator.Result,
                           hitPoints: CharacterSnapshot.HitPoints,
                           to record: CharacterRecord,
                           timestamp: Date) {
        record.strength = result.attributes.strength
        record.wisdom = result.attributes.wisdom
        record.spirit = result.attributes.spirit
        record.vitality = result.attributes.vitality
        record.agility = result.attributes.agility
        record.luck = result.attributes.luck
        record.maximumHP = result.hitPoints.maximum
        record.currentHP = hitPoints.current
        record.physicalAttack = result.combat.physicalAttack
        record.magicalAttack = result.combat.magicalAttack
        record.physicalDefense = result.combat.physicalDefense
        record.magicalDefense = result.combat.magicalDefense
        record.hitRate = result.combat.hitRate
        record.evasionRate = result.combat.evasionRate
        record.criticalRate = result.combat.criticalRate
        record.attackCount = result.combat.attackCount
        record.magicalHealing = result.combat.magicalHealing
        record.trapRemoval = result.combat.trapRemoval
        record.additionalDamage = result.combat.additionalDamage
        record.breathDamage = result.combat.breathDamage
        record.isMartialEligible = result.combat.isMartialEligible
        record.updatedAt = timestamp
    }

    func replaceAssociations(from snapshot: CharacterSnapshot,
                             context: ModelContext,
                             timestamp: Date) throws {
        let characterId = snapshot.id
        try deleteAssociations(for: characterId, context: context)

        for value in snapshot.explorationTags {
            let record = CharacterExplorationTagRecord(characterId: characterId,
                                                       value: value,
                                                       createdAt: timestamp,
                                                       updatedAt: timestamp)
            context.insert(record)
        }

        for skill in snapshot.learnedSkills {
            let record = CharacterSkillRecord(id: skill.id,
                                              characterId: characterId,
                                              skillId: skill.skillId,
                                              level: skill.level,
                                              isEquipped: skill.isEquipped,
                                              createdAt: skill.createdAt,
                                              updatedAt: skill.updatedAt)
            context.insert(record)
        }

        for item in snapshot.equippedItems {
            let record = CharacterEquipmentRecord(id: item.id,
                                                   characterId: characterId,
                                                   itemId: item.itemId,
                                                   quantity: item.quantity,
                                                   normalTitleId: item.normalTitleId,
                                                   superRareTitleId: item.superRareTitleId,
                                                   socketKey: item.socketKey,
                                                   createdAt: item.createdAt,
                                                   updatedAt: item.updatedAt)
            context.insert(record)
        }

        for entry in snapshot.jobHistory {
            let record = CharacterJobHistoryRecord(id: entry.id,
                                                   characterId: characterId,
                                                   jobId: entry.jobId,
                                                   achievedAt: entry.achievedAt,
                                                   createdAt: entry.createdAt,
                                                   updatedAt: entry.updatedAt)
            context.insert(record)
        }
    }

    func deleteAssociations(for characterId: UUID, context: ModelContext) throws {
        let skillDescriptor = FetchDescriptor<CharacterSkillRecord>(predicate: #Predicate { $0.characterId == characterId })
        let equipmentDescriptor = FetchDescriptor<CharacterEquipmentRecord>(predicate: #Predicate { $0.characterId == characterId })
        let jobDescriptor = FetchDescriptor<CharacterJobHistoryRecord>(predicate: #Predicate { $0.characterId == characterId })
        let tagDescriptor = FetchDescriptor<CharacterExplorationTagRecord>(predicate: #Predicate { $0.characterId == characterId })

        for record in try context.fetch(skillDescriptor) {
            context.delete(record)
        }
        for record in try context.fetch(equipmentDescriptor) {
            context.delete(record)
        }
        for record in try context.fetch(jobDescriptor) {
            context.delete(record)
        }
        for record in try context.fetch(tagDescriptor) {
            context.delete(record)
        }
    }

    func removeFromParties(characterId: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PartyMemberRecord>(predicate: #Predicate { $0.characterId == characterId })
        let members = try context.fetch(descriptor)
        guard !members.isEmpty else { return }
        let now = Date()
        var affectedPartyIds: Set<UUID> = []
        for member in members {
            affectedPartyIds.insert(member.partyId)
            context.delete(member)
        }
        for partyId in affectedPartyIds {
            try resequenceMembers(partyId: partyId, context: context, timestamp: now)
        }
    }

    func resequenceMembers(partyId: UUID, context: ModelContext, timestamp: Date) throws {
        let partyDescriptor = FetchDescriptor<PartyRecord>(predicate: #Predicate { $0.id == partyId })
        guard let party = try context.fetch(partyDescriptor).first else { return }
        let members = try fetchPartyMembers(partyId: partyId, context: context)
        for (index, member) in members.enumerated() {
            if member.order != index {
                member.order = index
                member.updatedAt = timestamp
            }
        }
        party.updatedAt = timestamp
    }

    func fetchPartyMembers(partyId: UUID, context: ModelContext) throws -> [PartyMemberRecord] {
        var descriptor = FetchDescriptor<PartyMemberRecord>(predicate: #Predicate { $0.partyId == partyId })
        descriptor.sortBy = [SortDescriptor(\PartyMemberRecord.order, order: .forward)]
        return try context.fetch(descriptor)
    }
}
