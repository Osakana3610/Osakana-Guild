import Foundation
import CloudKit

actor ProgressCloudKitCleanupService {

    private let container: CKContainer
    private let database: CKDatabase

    init(containerIdentifier: String = "iCloud.me.fishnchips.Epika") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    func purgeAllZones() async throws {
        let zoneIDs = try await fetchDeletableZoneIDs()
        guard !zoneIDs.isEmpty else { return }
        try await deleteZones(with: zoneIDs)
    }
}

private extension ProgressCloudKitCleanupService {
    func fetchDeletableZoneIDs() async throws -> [CKRecordZone.ID] {
        let zones = try await database.allRecordZones()
        let defaultZoneName = CKRecordZone.default().zoneID.zoneName
        return zones
            .map { $0.zoneID }
            .filter { $0.zoneName != defaultZoneName }
    }

    func deleteZones(with zoneIDs: [CKRecordZone.ID]) async throws {
        do {
            let result = try await database.modifyRecordZones(saving: [], deleting: zoneIDs)
            let blockingError = result.deleteResults.values.compactMap { outcome -> Error? in
                switch outcome {
                case .success:
                    return nil
                case .failure(let error):
                    return Self.isIgnorableZoneDeletionError(error) ? nil : error
                }
            }.first
            if let blockingError {
                throw blockingError
            }
        } catch {
            if Self.isIgnorableZoneDeletionError(error) {
                return
            }
            if let ckError = error as? CKError, ckError.code == .partialFailure {
                let blockingError = ckError.partialErrorsByItemID?
                    .values
                    .first { !Self.isIgnorableZoneDeletionError($0) }
                if blockingError == nil {
                    return
                }
            }
            throw error
        }
    }

    static func isIgnorableZoneDeletionError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .zoneNotFound
    }
}
