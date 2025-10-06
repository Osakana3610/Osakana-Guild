import CoreGraphics

enum AppConstants {
    enum UI {
        static let listRowHeight: CGFloat = 0
    }

    enum Progress {
        nonisolated static let defaultPartySlotCount = 1
        nonisolated static let maximumPartySlotsWithGold = 7
        nonisolated static let defaultCharacterSlotCount = 200

        static func partySlotExpansionCost(for nextSlot: Int) -> Int {
            // 旧実装と同じくゴールドコストは一定。
            nextSlot >= 2 && nextSlot <= maximumPartySlotsWithGold ? 1 : 0
        }
    }
}
