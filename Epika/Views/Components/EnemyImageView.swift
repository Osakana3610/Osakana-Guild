// ==============================================================================
// EnemyImageView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 敵キャラクターの画像を表示
//   - enemyIdに基づいてAssets.xcassetsから画像を取得
//
// 【View構成】
//   - Assets.xcassets/Enemies/{enemyId}から画像を表示
//   - 画像が存在しない場合はフォールバック表示（グレー+pawprint.fillアイコン）
//   - ダークモード対応（brightness調整）
//
// 【使用箇所】
//   - 戦闘画面
//   - 敵一覧画面
//
// ==============================================================================

import SwiftUI

/// 敵画像表示コンポーネント
/// enemyIdに基づいてAssets.xcassets/Characters/Enemies/{id}の画像を表示
struct EnemyImageView: View {
    let enemyId: UInt16
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(enemyId: UInt16, size: CGFloat = 55) {
        self.enemyId = enemyId
        self.size = size
    }

    var body: some View {
        let imageName = "Enemies/\(enemyId)"

        if UIImage(named: imageName) != nil {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .cornerRadius(8)
                .brightness(colorScheme == .dark ? 0.8 : 0)
        } else {
            fallbackView
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "pawprint.fill")
                    .foregroundColor(.primary)
                    .font(.system(size: size * 0.4))
            )
    }
}
