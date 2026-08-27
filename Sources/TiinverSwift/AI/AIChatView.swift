import PhotosUI
import SwiftUI

/// Port de `ai/TiinverGeminiAIChat.java` (823 lignes, entier, 2026-08-18 P2 — confirmé `PARTIAL`
/// par l'audit V2 : seule la couche de stockage `AiConversationRepository` était déjà portée,
/// l'écran lui-même jamais construit). 3 points d'entrée réels confirmés (`Roster.java:443`,
/// `MonetizationActivity.java:109`, `MainFragment.java:1456`, tous `Intent(TiinverGeminiAIChat
/// .class)` identiques) — câblé ici depuis `RosterListView` (toolbar), le plus direct.
struct AIChatView: View {
    @StateObject private var viewModel = AIChatViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let selectedImage = viewModel.selectedImage {
                selectedImagePreview(selectedImage)
            }
            inputBar
        }
        .navigationTitle("Assistant Tiina")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Port de `quotaCounter` — compteur d'usage affiché en permanence.
                Text("\(viewModel.quotaUsed)/\(viewModel.quotaLimit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await viewModel.loadInitial() }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    viewModel.selectedImage = image
                }
                pickerItem = nil
            }
        }
        // Port de `showInsufficientCoinsDialog`.
        .sheet(isPresented: Binding(get: { viewModel.insufficientCoinsBalance != nil }, set: { if !$0 { viewModel.insufficientCoinsBalance = nil } })) {
            insufficientCoinsSheet
        }
        .alert("Erreur", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.messages.isEmpty {
                        welcomeState
                    }
                    ForEach(viewModel.messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Demande-moi n'importe quoi, ou génère une image.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)

            // Port de `TiinverGeminiAIChat.setupChips` (`ai/TiinverGeminiAIChat.java:268-313`, lu
            // en entier) — **ajouté le 2026-08-27 (validation physique, BUG 5)**. Absent jusqu'ici :
            // seul l'état vide (`R.string.demande_moi...`) avait été porté, jamais les 2 groupes de
            // puces de suggestion Android (5 questions fréquentes + 3 prompts d'image + "améliorer
            // mon image"). Textes EXACTS de `values-fr/strings.xml` (`chip_gain_coins`/
            // `chip_create_animeme`/`chip_monetize`/`chip_paid_group`/`chip_withdraw`/
            // `chip_african_landscape`/`chip_artistic_portrait`/`chip_profile_illustration`/
            // `chip_improve_image`), pas devinés. Chaque puce réutilise la logique EXISTANTE plutôt
            // que d'en dupliquer une seconde : `setChipText`/`onChipTextClick` (question) →
            // `viewModel.inputText` + `sendText()` ; `setChipImage`/`onChipImageClick` (prompt
            // d'image) → `viewModel.inputText` + `generateImage()` ; `chip_improve_image` →
            // `galleryLauncher.launch("image/*")` côté Android, simple ouverture du même
            // `PhotosPicker` déjà câblé sur `$pickerItem` dans `inputBar` (aucun prompt auto-attaché
            // par Android non plus, vérifié : le handler Android n'ajoute aucun message).
            VStack(alignment: .leading, spacing: 10) {
                Text("Questions fréquentes").font(.subheadline.bold())
                ForEach(Self.questionChips, id: \.text) { chip in
                    chipButton(icon: chip.icon, tint: chip.tint, text: chip.text) {
                        Task { await ask(chip.text) }
                    }
                }

                Text("🎨 Générer une image").font(.subheadline.bold()).padding(.top, 8)
                ForEach(Self.imageChips, id: \.self) { prompt in
                    chipButton(icon: "photo.fill", tint: .orange, text: prompt, background: Color.yellow.opacity(0.12)) {
                        Task { await generateImage(prompt: prompt) }
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    chipLabel(icon: "plus.circle.fill", tint: .orange, text: "Améliorer mon image 📷", background: Color.yellow.opacity(0.12))
                }
            }
            .padding(.horizontal)
        }
    }

    /// Port de `values-fr/strings.xml`'s `chip_gain_coins`/`chip_create_animeme`/`chip_monetize`/
    /// `chip_paid_group`/`chip_withdraw` — ordre EXACT de `setupChips()`.
    private static let questionChips: [(icon: String, tint: Color, text: String)] = [
        ("dollarsign.circle.fill", .yellow, "Comment gagner des pièces sur Tiinver ?"),
        ("play.circle.fill", .black, "Comment créer un Animeme ?"),
        ("dollarsign.circle.fill", .green, "Comment monétiser mon compte Tiinver ?"),
        ("person.2.fill", .blue, "Comment créer un groupe payant ?"),
        ("wallet.pass.fill", .purple, "Comment retirer mes gains ?"),
    ]

    /// Port de `chip_african_landscape`/`chip_artistic_portrait`/`chip_profile_illustration`.
    private static let imageChips: [String] = [
        "Crée un paysage africain au coucher du soleil",
        "Génère un portrait artistique en style africain",
        "Crée une illustration pour mon profil Tiinver",
    ]

    private func chipButton(icon: String, tint: Color, text: String, background: Color = Color(.secondarySystemBackground), action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(icon: icon, tint: tint, text: text, background: background) }
            .buttonStyle(.plain)
    }

    private func chipLabel(icon: String, tint: Color, text: String, background: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(background, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Port de `onChipTextClick` — même chemin que le champ de saisie + bouton d'envoi normal.
    private func ask(_ question: String) async {
        viewModel.inputText = question
        await viewModel.sendText()
    }

    /// Port de `onChipImageClick` — même chemin que le champ de saisie + bouton "générer" normal.
    private func generateImage(prompt: String) async {
        viewModel.inputText = prompt
        await viewModel.generateImage()
    }

    @ViewBuilder
    private func bubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 0) }
            Group {
                if message.isPending {
                    ProgressView().frame(width: 40, height: 24)
                } else {
                    switch message.kind {
                    case .text(let text):
                        Text(text)
                    case .image(let url):
                        AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: 220, maxHeight: 220)
                    }
                }
            }
            .padding(10)
            .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            if message.role == .user { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func selectedImagePreview(_ image: UIImage) -> some View {
        HStack {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Image jointe").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { viewModel.selectedImage = nil } label: { Image(systemName: "xmark.circle.fill") }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo").font(.title3)
            }
            TextField("Message", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(viewModel.quotaReached)
                .textFieldStyle(.roundedBorder)
            if viewModel.selectedImage != nil {
                // Port du bouton "générer" quand une image est jointe — `checkCoinsAndGenerateImage`.
                Button { Task { await viewModel.generateImage() } } label: {
                    Image(systemName: "wand.and.stars")
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)
            } else {
                Button { Task { await viewModel.sendText() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending || viewModel.quotaReached)
            }
        }
        .padding()
        // Port de `disableInput(getString(R.string.tiina_quota_reached))`.
        .overlay(alignment: .top) {
            if viewModel.quotaReached {
                Text("Quota quotidien atteint").font(.caption2).foregroundStyle(.red).padding(.top, -14)
            }
        }
    }

    private var insufficientCoinsSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Solde insuffisant").font(.title2.bold())
                Text("Solde actuel : \(Int(viewModel.insufficientCoinsBalance ?? 0)) pièces")
                    .foregroundStyle(.secondary)
                // Port de `btn_earn_coins`/`btn_recharge` → `ReferralActivity`/`SelectAmountActivity`.
                NavigationLink("Gagner des pièces") { ReferralView() }
                    .buttonStyle(.bordered)
                NavigationLink("Recharger") { BuyCoinsView() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
