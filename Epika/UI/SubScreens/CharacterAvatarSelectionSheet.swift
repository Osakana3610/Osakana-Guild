// ==============================================================================
// CharacterAvatarSelectionSheet.swift
// Epika
// ==============================================================================
//
// 【責務】
//   - キャラクターのアバター画像選択機能を提供
//
// 【View構成】
//   - 種族イラストの一覧表示（avatarIndex 1〜18）
//   - 職業イラストの一覧表示（genderCode * 100 + jobIndex）
//   - ユーザーが読み込んだカスタム画像の一覧表示
//   - PhotosPickerによる画像インポート機能
//   - デフォルトに戻すボタン
//
// 【使用箇所】
//   - キャラクター詳細画面からシート表示
//
// ==============================================================================

import SwiftUI
import PhotosUI

struct CharacterAvatarSelectionSheet: View {
    let currentAvatarIndex: UInt16
    let defaultAvatarIndex: UInt16  // 通常はraceIndex（種族画像）
    let onSelect: (UInt16) -> Void

    @State private var importedAvatars: [UserAvatar] = []
    @State private var isLoadingImported = false
    @State private var importError: String?
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// 職業画像のavatarIndex一覧（genderCode * 100 + jobIndex）
    /// genderCode: 1=male, 2=female, 3=genderless
    /// jobIndex: 1〜16
    private var jobAvatarIndices: [UInt16] {
        var indices: [UInt16] = []
        for genderCode: UInt16 in 1...3 {
            for jobIndex: UInt16 in 1...16 {
                indices.append(genderCode * 100 + jobIndex)
            }
        }
        return indices
    }

    /// 種族画像のavatarIndex一覧（1〜18）
    private var raceAvatarIndices: [UInt16] {
        Array(1...18)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // デフォルトに戻すボタン
                    if currentAvatarIndex != 0 {
                        Button {
                            onSelect(0)  // 0=デフォルト（種族画像）
                        } label: {
                            HStack {
                                Spacer()
                                Text("デフォルトに戻す")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    avatarSection(title: "種族イラスト", indices: raceAvatarIndices)
                    avatarSection(title: "職業イラスト", indices: jobAvatarIndices)
                    importedSection
                }
                .padding()
            }
            .navigationTitle("アバターを選択")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedPhotoItem,
                                  matching: .images,
                                  photoLibrary: .shared()) {
                        Text("画像を読み込む")
                    }
                    .disabled(isLoadingImported)
                }
            }
            .task { await loadImported() }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if let item = newValue {
                    Task { await importFromPhotos(item: item) }
                }
            }
            .alert("画像の読み込みに失敗しました", isPresented: Binding(get: {
                importError != nil
            }, set: { value in
                if !value { importError = nil }
            })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                if let message = importError {
                    Text(message)
                }
            }
        }
    }

    private func avatarSection(title: String, indices: [UInt16]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(indices, id: \.self) { index in
                    avatarCell(avatarIndex: index, importedAvatar: nil)
                }
            }
        }
    }

    private var importedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("読み込んだ画像")
                    .font(.headline)
                if isLoadingImported {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if importedAvatars.isEmpty {
                Text("まだ読み込んだ画像はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(importedAvatars) { avatar in
                        if let index = UInt16(avatar.id) {
                            avatarCell(avatarIndex: index, importedAvatar: avatar)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func avatarCell(avatarIndex: UInt16, importedAvatar: UserAvatar?) -> some View {
        Button {
            onSelect(avatarIndex)
        } label: {
            ZStack(alignment: .topTrailing) {
                CharacterImageView(avatarIndex: avatarIndex, size: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isCurrent(avatarIndex) ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                if isCurrent(avatarIndex) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let avatar = importedAvatar {
                Button(role: .destructive) {
                    Task { await deleteAvatar(avatar) }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    private func isCurrent(_ index: UInt16) -> Bool {
        // 0=デフォルト（種族画像）の場合はdefaultAvatarIndexと比較
        if currentAvatarIndex == 0 {
            return index == defaultAvatarIndex
        }
        return index == currentAvatarIndex
    }

    private func loadImported() async {
        isLoadingImported = true
        defer { isLoadingImported = false }
        do {
            let avatars = try await UserAvatarStore.shared.list()
            await MainActor.run {
                importedAvatars = avatars
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }

    private func importFromPhotos(item: PhotosPickerItem) async {
        isLoadingImported = true
        defer {
            selectedPhotoItem = nil
            isLoadingImported = false
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw UserAvatarStore.AvatarStoreError.unsupportedImage
            }
            let saved = try await UserAvatarStore.shared.save(data: data)
            await MainActor.run {
                importedAvatars.insert(saved, at: 0)
                if let index = UInt16(saved.id) {
                    onSelect(index)
                }
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }

    private func deleteAvatar(_ avatar: UserAvatar) async {
        do {
            try await UserAvatarStore.shared.delete(identifier: avatar.id)
            await MainActor.run {
                importedAvatars.removeAll { $0.id == avatar.id }
                if let index = UInt16(avatar.id), currentAvatarIndex == index {
                    onSelect(0)  // デフォルトに戻す
                }
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }
}
