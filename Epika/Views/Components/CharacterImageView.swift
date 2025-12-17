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
        // 400以上はユーザーカスタムアバター
        if avatarIndex >= 400 {
            let identifier = String(avatarIndex)
            if let url = UserAvatarStore.fileURL(for: identifier) {
                return .file(url)
            }
            return nil
        } else if avatarIndex >= 100 {
            // 100-399: 職業画像 (genderCode * 100 + jobId)
            return .bundle("Jobs/\(avatarIndex)")
        } else {
            // 1-99: 種族画像 (raceId)
            return .bundle("Races/\(avatarIndex)")
        }
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
