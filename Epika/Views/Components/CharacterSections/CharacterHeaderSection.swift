import SwiftUI

/// キャラクターのヘッダー情報（名前 + アバター画像）を表示するセクション
/// CharacterSectionType: name, characterImage
@MainActor
struct CharacterHeaderSection: View {
    let character: RuntimeCharacter
    let onRename: ((String) async throws -> Void)?
    let onAvatarChange: ((String) async throws -> Void)?

    @State private var nameText: String
    @State private var renameError: String?
    @State private var isRenaming = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isAvatarSheetPresented = false
    @State private var avatarChangeError: String?
    @State private var isChangingAvatar = false

    init(character: RuntimeCharacter,
         onRename: ((String) async throws -> Void)? = nil,
         onAvatarChange: ((String) async throws -> Void)? = nil) {
        self.character = character
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        _nameText = State(initialValue: character.name)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            avatarView
            nameAndErrorView
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(alignment: .topLeading) {
            if isChangingAvatar {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
        .onChange(of: character.name) { _, newValue in
            nameText = newValue
        }
        .onChange(of: character.avatarIdentifier) { _, _ in
            avatarChangeError = nil
        }
        .sheet(isPresented: $isAvatarSheetPresented) {
            CharacterAvatarSelectionSheet(currentIdentifier: character.avatarIdentifier,
                                          defaultIdentifier: defaultAvatarIdentifier) { identifier in
                applyAvatarChange(identifier)
            }
        }
    }

    private var avatarView: some View {
        CharacterImageView(avatarIdentifier: character.avatarIdentifier, size: 60)
            .frame(width: 60, height: 60, alignment: .center)
            .overlay(alignment: .bottomTrailing) {
                if onAvatarChange != nil {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: -2, y: -2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard onAvatarChange != nil, !isChangingAvatar else { return }
                isAvatarSheetPresented = true
            }
    }

    private var nameAndErrorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if onRename != nil {
                HStack(spacing: 8) {
                    TextField("キャラクター名", text: $nameText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .disabled(isRenaming)
                        .focused($isNameFieldFocused)
                        .onSubmit { triggerRename() }
                        .onChange(of: nameText) { _, _ in renameError = nil }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: isNameFieldFocused) { _, focused in
                    if !focused {
                        triggerRename()
                    }
                }

                if let renameError {
                    Text(renameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text(character.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let avatarChangeError {
                Text(avatarChangeError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var defaultAvatarIdentifier: String? {
        try? CharacterAvatarIdentifierResolver.defaultAvatarIdentifier(jobId: character.jobId,
                                                                       genderRawValue: character.gender)
    }

    private func triggerRename() {
        guard let onRename else { return }
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameText = character.name
            renameError = "名前を入力してください"
            return
        }
        guard trimmed != character.name else {
            renameError = nil
            return
        }
        renameError = nil
        isRenaming = true
        Task {
            do {
                try await onRename(trimmed)
                await MainActor.run {
                    nameText = trimmed
                    renameError = nil
                    isRenaming = false
                }
            } catch {
                await MainActor.run {
                    renameError = error.localizedDescription
                    nameText = character.name
                    isRenaming = false
                }
            }
        }
    }

    private func applyAvatarChange(_ identifier: String) {
        guard let onAvatarChange else { return }
        avatarChangeError = nil
        isChangingAvatar = true
        Task {
            do {
                try await onAvatarChange(identifier)
                await MainActor.run {
                    isChangingAvatar = false
                    isAvatarSheetPresented = false
                }
            } catch {
                await MainActor.run {
                    isChangingAvatar = false
                    avatarChangeError = error.localizedDescription
                }
            }
        }
    }
}
