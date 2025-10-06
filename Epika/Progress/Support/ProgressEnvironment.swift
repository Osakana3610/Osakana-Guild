import Foundation

struct ProgressEnvironment {
    var masterDataService: MasterDataRuntimeService

    static var live: ProgressEnvironment {
        .init(masterDataService: .shared)
    }
}
