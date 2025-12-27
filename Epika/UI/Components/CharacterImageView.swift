// ==============================================================================
// CharacterImageView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターのアバター画像を統一的に表示
//   - avatarIndexに応じて種族/職業/カスタム画像を自動判別して表示
//
// 【View構成】
//   - avatarIndex範囲により画像リソースを判別:
//     - 1-99: 種族画像 (Assets.xcassets/Races/)
//     - 100-499: 職業画像 (Assets.xcassets/Jobs/)
//     - 500以上: ユーザーカスタムアバター (UserAvatarStore)
//   - 画像が存在しない場合はフォールバック表示（グレー+person.fillアイコン）
//   - ダークモード対応（brightness調整）
//
// 【使用箇所】
//   - キャラクター一覧画面
//   - パーティ編成画面
//   - キャラクター詳細画面
//
// ==============================================================================

import SwiftUI
import CoreGraphics
import ImageIO

/// 統一されたキャラクター画像表示コンポーネント
/// avatarIndexに基づいて画像を表示し、存在しない場合はフォールバックを提供
struct CharacterImageView: View {
    let avatarIndex: UInt16
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(avatarIndex: UInt16, size: CGFloat = 55) {
        self.avatarIndex = avatarIndex
        self.size = size
    }

    var body: some View {
        let resource = resolveResource()

        return Group {
            switch resource {
            case .bundle(let imageName):
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .cornerRadius(8)
                    .brightness(colorScheme == .dark ? 0.8 : 0)
            case .file(let url):
                if let cgImage = loadCGImage(from: url) {
                    Image(decorative: cgImage, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .cornerRadius(8)
                } else {
                    fallbackView
                }
            case .none:
                fallbackView
            }
        }
    }

    private enum ImageResource {
        case bundle(String)
        case file(URL)
    }

    private func resolveResource() -> ImageResource? {
        // 500以上はユーザーカスタムアバター
        if avatarIndex >= 500 {
            let identifier = String(avatarIndex)
            if let url = UserAvatarStore.fileURL(for: identifier) {
                return .file(url)
            }
            return nil
        } else if avatarIndex >= 100 {
            // 100-499: 職業画像 (genderCode * 100 + jobId)
            // マスター職(jobId 101-116)は基本職(1-16)の画像を使用
            let normalizedIndex = normalizeJobAvatarIndex(avatarIndex)
            return .bundle("Jobs/\(normalizedIndex)")
        } else {
            // 1-99: 種族画像 (raceId)
            return .bundle("Races/\(avatarIndex)")
        }
    }

    /// マスター職のavatarIndexを基本職に正規化
    /// - avatarIndex = genderCode * 100 + jobId で計算される
    /// - マスター職(jobId 101-116)の場合、100を引いて基本職の画像を使用
    /// - 例: 性別不明のマスター職1 (3*100+101=401) → 301
    private func normalizeJobAvatarIndex(_ index: UInt16) -> UInt16 {
        // 性別不明(genderCode=3)のマスター職は401-416の範囲
        // 女性(genderCode=2)のマスター職は301-316の範囲（性別不明基本職と衝突）
        // 男性(genderCode=1)のマスター職は201-216の範囲（女性基本職と衝突）
        // 現状アセットがない401-416のみ変換
        if index >= 400 {
            return index - 100
        }
        return index
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @ViewBuilder
    private var fallbackView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.primary)
                    .font(.system(size: size * 0.4))
            )
    }
}
