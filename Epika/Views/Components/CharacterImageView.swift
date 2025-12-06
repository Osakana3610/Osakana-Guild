import SwiftUI
import CoreGraphics
import ImageIO

/// 統一されたキャラクター画像表示コンポーネント
/// 種族・職業画像を指定されたサイズで表示し、存在しない場合はSFSymbolフォールバックを提供
struct CharacterImageView: View {
    enum ImageType {
        case avatar(index: UInt16)
        case race(id: String, gender: String)
        case job(id: String, gender: String)
    }

    let imageType: ImageType
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(imageType: ImageType, size: CGFloat = 55) {
        self.imageType = imageType
        self.size = size
    }

    init(avatarIndex: UInt16, size: CGFloat = 55) {
        self.init(imageType: .avatar(index: avatarIndex), size: size)
    }

    var body: some View {
        let resource = resolveResource()
        let fallbackIcon = getFallbackIcon()
        let fallbackText = getFallbackText()

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
                    fallbackView(icon: fallbackIcon, text: fallbackText)
                }
            case .none:
                fallbackView(icon: fallbackIcon, text: fallbackText)
            }
        }
    }

    private enum ImageResource {
        case bundle(String)
        case file(URL)
    }

    private func resolveResource() -> ImageResource? {
        do {
            switch imageType {
            case .avatar(let index):
                // 400以上はユーザーカスタムアバター
                if index >= 400 {
                    let identifier = String(index)
                    if let url = UserAvatarStore.fileURL(for: identifier) {
                        return .file(url)
                    }
                    return nil
                } else {
                    return .bundle(String(index))
                }
            case .race(let id, let gender):
                return .bundle(try CharacterAvatarIdentifierResolver.raceImagePath(raceId: id,
                                                                                    gender: gender))
            case .job(let id, let gender):
                return .bundle(try CharacterAvatarIdentifierResolver.jobImagePath(jobId: id,
                                                                                   gender: gender))
            }
        } catch {
            #if DEBUG
            assertionFailure("Character image path resolution failed: \(error)")
            #endif
            return nil
        }
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @ViewBuilder
    private func fallbackView(icon: String, text: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .foregroundColor(.primary)
                        .font(.system(size: size * 0.25))
                    Text(text)
                        .font(.system(size: size * 0.15))
                        .foregroundColor(.primary)
                }
            )
    }

    private func getFallbackIcon() -> String {
        switch imageType {
        case .avatar:
            return "person.fill"
        case .race(let id, _):
            return raceIcon(from: id)
        case .job(let id, _):
            return jobIcon(from: id)
        }
    }

    private func getFallbackText() -> String {
        switch imageType {
        case .avatar:
            return ""
        case .race(let id, _):
            return raceInitial(from: id)
        case .job(let id, _):
            return jobInitial(from: id)
        }
    }

    // MARK: - Job metadata for fallbacks

    private func jobIcon(from jobId: String) -> String {
        switch jobId {
        case "warrior": return "shield.fill"
        case "swordsman": return "figure.fencing"
        case "wizard": return "wand.and.stars"
        case "priest": return "cross.fill"
        case "thief": return "eye.slash.fill"
        case "hunter": return "scope"
        case "assassin": return "knife"
        case "jester": return "theatermasks.fill"
        case "monk": return "hands.clap.fill"
        case "samurai": return "figure.martial.arts"
        case "sword_saint": return "crown.fill"
        case "mystic_swordsman": return "sparkles"
        case "sage": return "book.fill"
        case "ninja": return "star.fill"
        case "lord": return "crown.fill"
        case "royal_line": return "star.circle.fill"
        default: return "person.fill"
        }
    }

    private func jobInitial(from jobId: String) -> String {
        switch jobId {
        case "warrior": return "戦"
        case "swordsman": return "剣"
        case "wizard": return "魔"
        case "priest": return "僧"
        case "thief": return "盗"
        case "hunter": return "狩"
        case "assassin": return "暗"
        case "jester": return "道"
        case "monk": return "修"
        case "samurai": return "侍"
        case "sword_saint": return "聖"
        case "mystic_swordsman": return "秘"
        case "sage": return "賢"
        case "ninja": return "忍"
        case "lord": return "君"
        case "royal_line": return "王"
        default: return "？"
        }
    }

    // MARK: - Race metadata for fallbacks

    private func raceIcon(from raceId: String) -> String {
        switch raceId {
        case "human": return "person.fill"
        case "elf": return "leaf.fill"
        case "dwarf": return "hammer.fill"
        case "gnome": return "circle.fill"
        case "pigmy_chum": return "smallcircle.fill.circle"
        case "dark_elf": return "moon.fill"
        case "vampire": return "drop.fill"
        case "psychic": return "brain.head.profile"
        case "working_cat": return "cat.fill"
        case "dragonewt": return "flame.fill"
        case "amazon": return "shield.fill"
        case "magic_construct": return "gear.circle.fill"
        case "undead_man": return "skull.fill"
        case "giant": return "mountain.2.fill"
        case "tengu": return "bird.fill"
        case "demon": return "horn.fill"
        case "cyborg": return "cpu.fill"
        default: return "person.fill"
        }
    }

    private func raceInitial(from raceId: String) -> String {
        switch raceId {
        case "human": return "人"
        case "elf": return "エ"
        case "dwarf": return "ド"
        case "gnome": return "ノ"
        case "pigmy_chum": return "ピ"
        case "dark_elf": return "ダ"
        case "vampire": return "吸"
        case "psychic": return "サ"
        case "working_cat": return "猫"
        case "dragonewt": return "竜"
        case "amazon": return "ア"
        case "magic_construct": return "魔"
        case "undead_man": return "死"
        case "giant": return "巨"
        case "tengu": return "天"
        case "demon": return "鬼"
        case "cyborg": return "機"
        default: return "？"
        }
    }
}
