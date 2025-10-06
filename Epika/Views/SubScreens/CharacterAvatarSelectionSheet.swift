import SwiftUI
import PhotosUI

struct CharacterAvatarSelectionSheet: View {
    let currentIdentifier: String
    let defaultIdentifier: String?
    let onSelect: (String) -> Void

    @State private var jobAvatars: [String] = CharacterAvatarIdentifierResolver.defaultJobAvatarIdentifiers
    @State private var raceAvatars: [String] = CharacterAvatarIdentifierResolver.defaultRaceAvatarIdentifiers
    @State private var importedAvatars: [UserAvatar] = []
    @State private var isLoadingImported = false
    @State private var importError: String?
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let defaultIdentifier {
                        Button {
                            onSelect(defaultIdentifier)
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
                    avatarSection(title: "職業イラスト", identifiers: jobAvatars)
                    avatarSection(title: "種族イラスト", identifiers: raceAvatars)
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

    private func avatarSection(title: String, identifiers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(identifiers, id: \.self) { identifier in
                        avatarCell(identifier: identifier, importedAvatar: nil)
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
                        avatarCell(identifier: avatar.id, importedAvatar: avatar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func avatarCell(identifier: String, importedAvatar: UserAvatar?) -> some View {
        Button {
            onSelect(identifier)
        } label: {
            ZStack(alignment: .topTrailing) {
                CharacterImageView(avatarIdentifier: identifier, size: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isCurrent(identifier) ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                if isCurrent(identifier) {
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

    private func isCurrent(_ identifier: String) -> Bool {
        identifier == currentIdentifier
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
                onSelect(saved.id)
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
                if currentIdentifier == avatar.id {
                    if let defaultIdentifier {
                        onSelect(defaultIdentifier)
                    } else if let firstDefault = CharacterAvatarIdentifierResolver.defaultJobAvatarIdentifiers.first {
                        onSelect(firstDefault)
                    }
                }
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }
}
