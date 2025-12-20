// ==============================================================================
// UserAvatarStore.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - ユーザーアバター画像のファイル管理（保存・削除・一覧取得）
//   - 画像のリサイズとモノクロ加工処理
//   - メモリ効率を考慮したサムネイル生成
//
// 【公開API】
//   - shared: シングルトンインスタンス（actor）
//   - list(): 保存済みアバター一覧の取得
//   - save(data:): 新規アバターの保存（自動リサイズ・モノクロ加工）
//   - delete(identifier:): アバターの削除
//   - isUserAvatarIdentifier(_:): ユーザーアバター識別子の判定
//   - fileURL(for:): 識別子からファイルURLの取得
//
// 【使用箇所】
//   - キャラクター作成・編集画面でのアバター選択
//   - アバター管理画面での一覧表示・削除
//
// ==============================================================================

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

struct UserAvatar: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date

    var fileName: String {
        url.lastPathComponent
    }
}

actor UserAvatarStore {
    static let shared = UserAvatarStore()

    static let identifierPrefix = "user:"
    static let targetPixelDimension: CGFloat = 240

    private let directory: URL
    private let fileManager: FileManager

    enum AvatarStoreError: Error, LocalizedError {
        case unsupportedImage
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedImage:
                return "サポートされていない画像です"
            case .imageEncodingFailed:
                return "画像の保存に失敗しました"
            }
        }
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let target = documents.appendingPathComponent("UserAvatars", isDirectory: true)
        if !fileManager.fileExists(atPath: target.path) {
            try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        }
        directory = target
    }

    static func isUserAvatarIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func fileURL(for identifier: String) -> URL? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let fileName = String(identifier.dropFirst(identifierPrefix.count))
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("UserAvatars", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func list() throws -> [UserAvatar] {
        let contents = try fileManager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: [.skipsHiddenFiles])
        return contents.compactMap { url in
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let date = (attributes?[.modificationDate] as? Date) ?? Date()
            let id = Self.identifierPrefix + url.lastPathComponent
            return UserAvatar(id: id, url: url, createdAt: date)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(data: Data) throws -> UserAvatar {
        let processedData = try Self.preparePNGData(from: data, maxDimension: Self.targetPixelDimension)
        let fileName = UUID().uuidString + ".png"
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try processedData.write(to: url, options: .atomic)
        return UserAvatar(id: Self.identifierPrefix + fileName, url: url, createdAt: Date())
    }

    func delete(identifier: String) throws {
        guard let url = url(for: identifier) else { return }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

private extension UserAvatarStore {
    private static let ciContext = CIContext(options: nil)

    static func preparePNGData(from data: Data, maxDimension: CGFloat) throws -> Data {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw AvatarStoreError.unsupportedImage
        }

        // 読み込み時点で縮小（メモリ効率化：原寸展開を避ける）
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw AvatarStoreError.unsupportedImage
        }

        let processed = try applyMonoEffect(to: cgImage)
        return try pngData(from: processed)
    }

    static func applyMonoEffect(to image: CGImage) throws -> CGImage {
        var ciImage = CIImage(cgImage: image)

        let monoFilter = CIFilter.photoEffectMono()
        monoFilter.inputImage = ciImage
        if let output = monoFilter.outputImage {
            ciImage = output
        }

        let targetRect = ciImage.extent.integral
        guard let result = ciContext.createCGImage(ciImage, from: targetRect) else {
            throw AvatarStoreError.imageEncodingFailed
        }
        return result
    }

    static func pngData(from image: CGImage) throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0) else {
            throw AvatarStoreError.imageEncodingFailed
        }
        guard let destination = CGImageDestinationCreateWithData(mutableData,
                                                                 UTType.png.identifier as CFString,
                                                                 1,
                                                                 nil) else {
            throw AvatarStoreError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AvatarStoreError.imageEncodingFailed
        }
        return mutableData as Data
    }

    static func orientation(from properties: [CFString: Any]) -> CGImagePropertyOrientation? {
        if let raw = properties[kCGImagePropertyOrientation] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: raw) {
            return orientation
        }
        return nil
    }

    func url(for identifier: String) -> URL? {
        guard identifier.hasPrefix(Self.identifierPrefix) else { return nil }
        let fileName = String(identifier.dropFirst(Self.identifierPrefix.count))
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
