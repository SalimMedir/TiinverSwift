import SwiftUI

/// Port de `ui/categorie/CategoryActivity.java` (lu en entier) — **ajouté le 2026-08-19
/// (MIGRATION_PARITY_AUDIT_V3.md V3-F-058 PROFILE-03, Phase B P1)**, écran entièrement absent côté
/// iOS jusqu'ici malgré le champ `User.category` déjà décodé. Liste à sélection unique des 37
/// catégories réelles (`CategoryActivity.java:61-120`, IDs et libellés exacts, y compris les emoji
/// des vraies chaînes `values-fr/strings.xml` — reprises verbatim, pas retraduites). Bouton
/// "Enregistrer" désactivé tant qu'aucune catégorie n'est sélectionnée (`btnSave.setEnabled(false)`
/// initial, activé seulement après un choix — `CategoryAdapter`'s callback), fidèle à l'original.
///
/// Réutilisé dans 2 contextes : (1) édition libre depuis les réglages de compte, (2) sélection
/// FORCÉE avant publication quand le compte n'a pas encore de catégorie (voir `PublishComposeView`,
/// port de `PublishFragment.java:274-283` qui lance `CategoryActivity` et bloque la publication tant
/// qu'aucun choix n'a été fait).
struct CategoryOption: Identifiable, Equatable {
    let id: String
    let label: String
}

enum CategoryCatalog {
    /// Ordre et regroupements EXACTS de `CategoryActivity.java:61-120` (les commentaires de section
    /// Android — 🍽️ Alimentation, 💪 Santé & Sport, etc. — ne sont que des commentaires Java, PAS
    /// des en-têtes de section dans le `RecyclerView` réel, une seule liste plate reproduite ici).
    static let all: [CategoryOption] = [
        CategoryOption(id: "food_cooking", label: "🧑‍🍳 Cuisine et cuisine"),
        CategoryOption(id: "food_beverages", label: "🥤 Alimentation et boissons"),
        CategoryOption(id: "restaurant_bar", label: "🍽️ Restaurant et bar"),
        CategoryOption(id: "fitness_health", label: "💪 Forme et santé"),
        CategoryOption(id: "health_wellness", label: "🏥 Santé & Bien-être"),
        CategoryOption(id: "sport", label: "⚽ Sport"),
        CategoryOption(id: "art_creativity", label: "🎨 Art et créativité"),
        CategoryOption(id: "photography", label: "📷 Photographie"),
        CategoryOption(id: "dance", label: "💃 Danse"),
        CategoryOption(id: "music_audio", label: "🎵 Musique & Audio"),
        CategoryOption(id: "diy_crafts", label: "🔨 Bricolage & Artisanat"),
        CategoryOption(id: "short_films", label: "🎥 Courts-métrages"),
        CategoryOption(id: "animation_cartoon", label: "🎬 Dessins Animés"),
        CategoryOption(id: "anime", label: "⛩️ Anime & Manga"),
        CategoryOption(id: "animation_kids", label: "🧸 Dessins Animés pour Enfants"),
        CategoryOption(id: "gaming", label: "🎮 Jeux vidéo"),
        CategoryOption(id: "technology", label: "🚀 Technologie"),
        CategoryOption(id: "software_apps", label: "💻 Logiciels et applications"),
        CategoryOption(id: "education_tips", label: "🧠 Éducation et conseils"),
        CategoryOption(id: "finance_money", label: "💰 Finance & Argent"),
        CategoryOption(id: "fashion_clothing", label: "👗 Vêtements et accessoires"),
        CategoryOption(id: "beauty_makeup", label: "💄 Beauté & Maquillage"),
        CategoryOption(id: "travel_adventure", label: "✈️ Voyages et aventure"),
        CategoryOption(id: "lifestyle_vlog", label: "❤️ Style de vie et vlog"),
        CategoryOption(id: "comedy_humor", label: "😂 Comédie & Humour"),
        CategoryOption(id: "kids_family", label: "👨‍👩‍👧 Enfants & Famille"),
        CategoryOption(id: "agriculture", label: "🌱 Agriculture"),
        CategoryOption(id: "livestock_farming", label: "🐄 Élevage"),
        CategoryOption(id: "beekeeping", label: "🐝 Apiculture"),
        CategoryOption(id: "fish_farming", label: "🐟 Pisciculture (Aquaculture)"),
        CategoryOption(id: "real_estate", label: "🏠 Immobilier"),
        CategoryOption(id: "automotive", label: "🚗 Automobile"),
        CategoryOption(id: "professional_services", label: "🧑‍💼 Services professionnels"),
        CategoryOption(id: "business_account", label: "🏢 Compte professionnel"),
        CategoryOption(id: "animals_pets", label: "🐶 Animaux et animaux de compagnie"),
        CategoryOption(id: "news_society", label: "🌍 Actualités et société"),
        CategoryOption(id: "gossip_trends", label: "🗣️ Potins et sujets tendance"),
        CategoryOption(id: "spirituality_motivation", label: "🔮 Spiritualité et motivation"),
        CategoryOption(id: "media_entertainment", label: "🎬 Médias et divertissement"),
    ]

    static func label(forId id: String?) -> String? {
        guard let id else { return nil }
        return all.first { $0.id == id }?.label
    }
}

struct CategoryPickerView: View {
    var currentCategoryId: String?
    /// Appelé APRÈS confirmation serveur réussie (`updateProfileField`), avec l'id choisi.
    var onSaved: (String) -> Void
    var onCancel: () -> Void

    @State private var selection: String?
    @State private var isSaving = false
    @State private var errorText: String?

    init(currentCategoryId: String? = nil, onSaved: @escaping (String) -> Void, onCancel: @escaping () -> Void = {}) {
        self.currentCategoryId = currentCategoryId
        self.onSaved = onSaved
        self.onCancel = onCancel
        _selection = State(initialValue: currentCategoryId)
    }

    var body: some View {
        NavigationStack {
            List(CategoryCatalog.all) { option in
                Button {
                    selection = option.id
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if selection == option.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Choisir une catégorie") // Port de "Choose category" (CategoryActivity.java:44)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") { Task { await save() } }
                            .disabled(selection == nil) // Port de `btnSave.setEnabled(false)` initial.
                    }
                }
            }
            .alert("Erreur", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    /// Port de `updateProfileData(String category)` (`CategoryActivity.java:155-167`) — `POST user`
    /// avec `column="category"`, réutilise `ProfileRepository.updateProfileField` déjà établi.
    private func save() async {
        guard let selection, let userId = UserSession.shared.myId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await ProfileRepository.shared.updateProfileField(userId: userId, column: "category", value: selection)
            onSaved(selection)
        } catch {
            errorText = "Impossible d'enregistrer la catégorie : \(error.localizedDescription)"
        }
    }
}
