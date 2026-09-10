import SwiftUI
import PhotosUI

// ─────────────────────────────────────────────────
// ÉDITION DU PROFIL — création (onboarding) ou modification
// ─────────────────────────────────────────────────
struct EditProfileView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss

    let isOnboarding: Bool

    @State private var username: String
    @State private var age: Int?
    @State private var sex: Sex?
    @State private var position: PlayerPosition?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?

    init(isOnboarding: Bool) {
        self.isOnboarding = isOnboarding
        let existing = ProfileStore.shared.profile
        _username  = State(initialValue: existing?.username ?? "")
        _age       = State(initialValue: existing?.age)
        _sex       = State(initialValue: existing?.sex)
        _position  = State(initialValue: existing?.position)
        _photoData = State(initialValue: existing?.photoData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable().scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill.badge.plus")
                                    .font(.system(size: 88))
                                    .foregroundStyle(.orange.opacity(0.6))
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Pseudo") {
                    TextField("Ton pseudo", text: $username)
                }

                Section("Infos") {
                    Stepper(age.map { "\($0) ans" } ?? "Âge non renseigné",
                            value: Binding(get: { age ?? 18 }, set: { age = $0 }), in: 6...99)

                    Picker("Sexe", selection: $sex) {
                        Text("—").tag(Sex?.none)
                        ForEach(Sex.allCases) { s in Text(s.label).tag(Sex?.some(s)) }
                    }

                    Picker("Poste", selection: $position) {
                        Text("—").tag(PlayerPosition?.none)
                        ForEach(PlayerPosition.allCases) { p in Text(p.label).tag(PlayerPosition?.some(p)) }
                    }
                }
            }
            .navigationTitle(isOnboarding ? "Compléter mon profil" : "Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .foregroundStyle(.orange)
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                Task {
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return }
                    let resized = uiImage.preparingThumbnail(of: CGSize(width: 300, height: 300)) ?? uiImage
                    photoData = resized.jpegData(compressionQuality: 0.8)
                }
            }
        }
    }

    private func save() {
        let draft = UserProfile(
            username: username.trimmingCharacters(in: .whitespaces),
            age: age,
            sex: sex,
            position: position,
            photoData: photoData,
            statsSummary: .empty
        )
        profileStore.save(draft)
        dismiss()
    }
}
