import Foundation
import SwiftData

@MainActor
final class ProgressBootstrapper {
    struct BootstrapResult {
        let container: ModelContainer
    }

    static let shared = ProgressBootstrapper()

    private var cachedContainer: ModelContainer?

    private init() {}

    func boot(cloudKitEnabled: Bool = false) async throws -> BootstrapResult {
        if let container = cachedContainer {
#if DEBUG
            print("[ProgressStore][DEBUG] reuse cached container")
#endif
            return BootstrapResult(container: container)
        }

#if DEBUG
        print("[ProgressStore][DEBUG] boot start")
#endif
        registerTransformersIfNeeded()

        let schema = Schema(ProgressModelSchema.modelTypes)
        let storeURL = try progressStoreURL()
#if DEBUG
        print("[ProgressStore][DEBUG] store URL: \(storeURL.path)")
#endif
        let configuration = makeConfiguration(schema: schema, storeURL: storeURL)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
#if DEBUG
            print("[ProgressStore][DEBUG] ModelContainer initialized")
#endif
        } catch {
#if DEBUG
            print("[ProgressStore][ERROR] first ModelContainer init failed: \(error)")
#endif
            do {
                try FileManager.default.removeItem(at: storeURL)
#if DEBUG
                print("[ProgressStore][DEBUG] removed corrupt store")
#endif
            } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
                // 既存ストアが存在しない場合は問題なし
            } catch let removeError {
                throw removeError
            }
            let retryConfig = makeConfiguration(schema: schema, storeURL: storeURL)
            container = try ModelContainer(for: schema, configurations: [retryConfig])
#if DEBUG
            print("[ProgressStore][DEBUG] ModelContainer initialized after reset")
#endif
        }
        cachedContainer = container
#if DEBUG
        print("[ProgressStore][DEBUG] boot finished")
#endif
        return BootstrapResult(container: container)
    }

    func resetStore() throws {
        cachedContainer = nil
        let storeURL = try progressStoreURL()
        do {
            try FileManager.default.removeItem(at: storeURL)
#if DEBUG
            print("[ProgressStore][DEBUG] reset removed store at \(storeURL.path)")
#endif
        } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
            // 削除対象が存在しない場合は問題なし
        } catch let removeError {
            throw removeError
        }
    }

    private func makeConfiguration(schema: Schema,
                                   storeURL: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema,
                           url: storeURL)
    }

    private func registerTransformersIfNeeded() {
#if DEBUG
        print("[ProgressStore][DEBUG] register transformers")
#endif
        // StatusEffectIdsTransformer は旧ExplorationEventRecord用で、現在は不要
    }

    private func progressStoreURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)
        let directory = support.appendingPathComponent("Epika", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("Progress.store")
    }
}
