import Foundation
import SwiftData

@Model
final class ProgressMetadataRecord {
    var id: UUID = UUID()
    var identifier: String = ProgressMetadataRecord.defaultIdentifier
    var schemaVersion: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastSyncedAt: Date?
    var superRareStateDateJST: String?
    var superRareTriggered: Bool = false

    init(id: UUID = UUID(),
         identifier: String = ProgressMetadataRecord.defaultIdentifier,
         schemaVersion: Int = 1,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastSyncedAt: Date? = nil,
         superRareStateDateJST: String? = nil,
         superRareTriggered: Bool = false) {
        self.id = id
        self.identifier = identifier
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
        self.superRareStateDateJST = superRareStateDateJST
        self.superRareTriggered = superRareTriggered
    }
}

extension ProgressMetadataRecord {
    static let defaultIdentifier = "progress_metadata_root"
}
