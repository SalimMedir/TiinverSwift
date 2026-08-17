import SwiftUI

/// Port de `wallet/MonetizationActivity.java` (117 lignes, lu en entier le 2026-08-17) — écran
/// hub des actions qui aident à monétiser son compte, écran DISTINCT de `WalletView` (solde/
/// retrait/achat de pièces). Le bouton "monétisation" de `ProfileView.actionRow` routait
/// AUPARAVANT vers `WalletView` faute d'avoir identifié cette Activity séparée — corrigé après
/// relecture complète du code Android, qui confirme bien `MonetizationActivity`/
/// `activity_monegtization.xml` comme écran indépendant.
///
/// **`button_2` ("Contact.class")** : vérifié dans `contacts/Contact.java` — lance
/// `ContactsFragment.newInstance(user)` à la position 0, EXACTEMENT la même fragment que le point
/// d'entrée "créer un groupe" du Chat (`ContactPickerView.swift` déjà porté) — réutilisé ici tel
/// quel, pas une approximation : Android partage réellement ce même écran entre les deux usages.
///
/// **PAS porté, gap documenté** : `ask_ai` → `TiinverGeminiAIChat` (assistant IA Gemini, aucun
/// écran équivalent construit dans ce portage — fonctionnalité entière hors périmètre, pas un
/// oubli). Bouton correspondant OMIS plutôt que simulé.
struct MonetizationView: View {
    @State private var showCamera = false
    @State private var pendingMedia: PublishMedia?
    @State private var pendingTrimURL: URL?
    @State private var showContactPicker = false
    @State private var showReferral = false
    @State private var showAnimems = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monétisation").font(.title2.bold())
                    Text("Boostez vos revenus sur Tiinver grâce à ces actions.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                // Port de `container_animemes` (visible seulement si la récompense de création
                // d'animation n'a pas déjà été réclamée) — reproduit fidèlement via la même clé
                // `ANIMEMES_CREATION_REWARD` déjà utilisée ailleurs dans le portage Wallet.
                if !UserDefaults.standard.bool(forKey: "ANIMEMES_CREATION_REWARD") {
                    actionCard(
                        icon: "sparkles.tv.fill", tint: .purple,
                        title: "Créez votre animation", subtitle: "Gagnez une récompense pour votre première création Animems"
                    ) { showAnimems = true }
                }

                actionCard(icon: "camera.fill", tint: .blue, title: "Publier du contenu", subtitle: "Partagez une photo ou une vidéo") {
                    showCamera = true
                }
                actionCard(icon: "person.2.fill", tint: .green, title: "Inviter des contacts", subtitle: "Faites connaître Tiinver autour de vous") {
                    showContactPicker = true
                }
                actionCard(icon: "gift.fill", tint: .orange, title: "Parrainage", subtitle: "Gagnez des pièces en parrainant vos amis") {
                    showReferral = true
                }

                AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle("Monétisation")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onClose: { showCamera = false },
                onPhotoCaptured: { image in showCamera = false; pendingMedia = .photo(image) },
                onVideoRecorded: { url, _ in showCamera = false; pendingMedia = .video(url) },
                onImagePickedFromGallery: { url in
                    showCamera = false
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        pendingMedia = .photo(image)
                    }
                },
                onVideoPickedFromGallery: { url in showCamera = false; pendingTrimURL = url },
                onOpenAnimems: { showCamera = false; showAnimems = true }
            )
        }
        .fullScreenCover(item: $pendingMedia) { media in
            PublishComposeView(media: media, onPublished: { pendingMedia = nil }, onCancel: { pendingMedia = nil })
        }
        .fullScreenCover(isPresented: Binding(get: { pendingTrimURL != nil }, set: { if !$0 { pendingTrimURL = nil } })) {
            if let url = pendingTrimURL {
                MediaTrimView(
                    sourceURL: url,
                    onTrimmed: { trimmedURL in pendingTrimURL = nil; pendingMedia = .video(trimmedURL) },
                    onCancel: { pendingTrimURL = nil }
                )
            }
        }
        .sheet(isPresented: $showContactPicker) {
            NavigationStack { ContactPickerView() }
        }
        .sheet(isPresented: $showReferral) {
            NavigationStack { ReferralView() }
        }
        .fullScreenCover(isPresented: $showAnimems) {
            AnimemesEditorView(onClose: { showAnimems = false })
        }
    }

    private func actionCard(icon: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
