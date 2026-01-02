// ==============================================================================
// PriceView.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - 価格を通貨種別（GP/キャット・チケット/ジェム）に応じて表示
//   - 大きな数値を省略形（1K、1M）で表示
//
// 【View構成】
//   - 金額 + 通貨アイコンを横並び表示
//   - 通貨種別:
//     - gold: "GP"テキスト
//     - catTicket: ticket.fillアイコン
//     - gem: diamond.fillアイコン
//   - 1000以上は1K、1000000以上は1M形式で省略
//
// 【使用箇所】
//   - ショップ画面
//   - アイテム一覧（InventoryItemRow内）
//   - 装備購入/売却画面
//
// ==============================================================================

import SwiftUI

struct PriceView: View {
    let price: Int
    let currencyType: CurrencyType
    let isAffordable: Bool

    init(price: Int, currencyType: CurrencyType = .gold, isAffordable: Bool = true) {
        self.price = price
        self.currencyType = currencyType
        self.isAffordable = isAffordable
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(formatPrice(price))
                .font(.headline)
                .foregroundColor(.primary)

            currencyIcon
                .foregroundColor(.primary)
        }
    }

    private var currencyIcon: some View {
        Group {
            switch currencyType {
            case .gold:
                Text("GP")
                    .font(.caption)
                    .bold()
            case .catTicket:
                Image(systemName: "ticket.fill")
                    .font(.caption)
            case .gem:
                Image(systemName: "diamond.fill")
                    .font(.caption)
            }
        }
    }

    private func formatPrice(_ price: Int) -> String {
        if price >= 1000000 {
            return String(format: "%.1fM", Double(price) / 1000000.0)
        } else if price >= 1000 {
            return String(format: "%.1fK", Double(price) / 1000.0)
        } else {
            return "\(price)"
        }
    }
}
 
