import SwiftUI

/// Port de `creatorOfweek/CreatorFragment.java` (218 lignes, lu en entier) — classement hebdomadaire
/// des créateurs ("Créateurs" dans la barre de navigation, `HomeShellView.swift`), le module que
/// `TIINVER_IOS_PORT_ANALYSIS.md`/`MIGRATION_PROGRESS.md` documentaient comme "jamais identifié dans
/// les 18 modules de l'ordre de portage" — confirmé par cette lecture : `creatorOfweek/` (3 fichiers
/// Java, `CreatorFragment`/`CreatorAdapter`/`CreatorModel`, + `TrophyViewModel`/`TrophyRepository`)
/// n'appartient à AUCUN module de l'ordre de portage original, mini-module autonome ajouté ici après
/// découverte via test interactif (Appetize.io).
///
/// Comportement RÉEL confirmé par lecture (pas deviné depuis le nom `CreatorFragment`) : le premier
/// élément du classement devient une carte "star" mise en avant (nom/score/photo, `creatorList.
/// get(0)`), les éléments RESTANTS (`remaining`, `creatorList` moins l'élément 0) forment la liste
/// classée en dessous — badge `"TOP " + (position+1)` calculé sur l'INDEX DANS LA LISTE RESTANTE,
/// PAS sur le rang global (donc la liste sous la star recommence à "TOP 1", comportement Android
/// réel reproduit tel quel, pas "corrigé").
///
/// **PAS porté, décoratif/hors périmètre du cœur fonctionnel** : confettis (`KonfettiView`),
/// animation de badge (scale infini), bannière AdMob (`adView` — un emplacement de plus que les 11
/// déjà cartographiés au module 16, non ajouté à `AdMobIdentifiers.swift` sans un vrai ID de
/// production à vérifier), réessai automatique après erreur (`attemptReconnectOverview`, délai fixe
/// 5s — remplacé par un bouton "Réessayer" manuel, plus simple et plus prévisible côté iOS).
/// **Parité UI avec Android corrigée par capture d'écran (2026-08-16)** — thème SOMBRE réel
/// (`R.style` de `CreatorFragment`, confirmé par capture, pas un `List` système clair comme la
/// version précédente de ce fichier), titre/description repris VERBATIM de `strings.xml`
/// (`creators_of_the_week`/`creators_ranked`, trouvés en cherchant le texte exact de la capture
/// plutôt que retranscrits approximativement), carte "star" mise en avant avec badge "STAR" rose
/// et anneau/dégradé de marque plutôt qu'une simple icône étoile superposée.
struct CreatorOfWeekView: View {
    @StateObject private var viewModel = CreatorOfWeekViewModel()
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-028, Phase B P2)** — port de
    /// `CreatorFragment.onResume` (`:160-164`, `viewModel.getTrophy()` à CHAQUE fois que le
    /// fragment redevient visible, pas seulement au premier affichage). `HomeShellView` héberge cet
    /// écran dans un onglet `TabView` PERSISTANT (jamais recréé entre deux sélections d'onglet,
    /// contrairement à une navigation push/pop) — `.task`/`.onAppear` ne se redéclenchent donc
    /// JAMAIS après le tout premier affichage, aucun équivalent SwiftUI direct d'`onResume` pour un
    /// onglet `TabView`. `isActive` (calculé par l'appelant à partir de son `selectedTab`) donne le
    /// même signal "cet onglet redevient visible" sans coupler cet écran au numéro de son propre
    /// onglet.
    var isActive: Bool = true

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error:
                errorState
            case .loaded(let star, let remaining):
                if let star {
                    content(star: star, remaining: remaining)
                } else {
                    emptyState
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Classement")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load() }
        .onChange(of: isActive) { active in
            if active { Task { await viewModel.load() } }
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text("Impossible de charger le classement").foregroundStyle(.white.opacity(0.7))
            Button("Réessayer") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            // R.string.no_creators_this_week (strings.xml:788), verbatim.
            Text("😔 Aucun créateur cette semaine").foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func content(star: CreatorModel, remaining: [CreatorModel]) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // R.string.creators_of_the_week (strings.xml:782), verbatim.
                    Text("🏆 Créateurs de la semaine").font(.title2.bold()).foregroundStyle(.white)
                    // R.string.creators_ranked (strings.xml:790), verbatim.
                    Text("🔥 Les créateurs classés cette semaine activent automatiquement la monétisation pour toute la durée de leur règne, quels que soient les critères habituels.")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)

                // Corrigé (V3-F-094, SILENT-05) : `CreatorAdapter.java:59-64` n'ouvre `UserProfile`
                // QUE si `idStr` est non-nul/non-vide (`if (idStr == null || idStr.trim().isEmpty())
                // return;`), sinon le tap est un no-op — reproduit ici via `.disabled(...)` plutôt
                // que de naviguer vers un `ProfileView(userId: "")` cassé.
                NavigationLink {
                    ProfileView(userId: star.userId ?? "", isCurrentUser: false)
                } label: {
                    starCard(star)
                }
                .disabled((star.userId ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.black)
            }
            Section {
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, creator in
                    NavigationLink {
                        ProfileView(userId: creator.userId ?? "", isCurrentUser: false)
                    } label: {
                        rankRow(creator, badge: "TOP \(index + 1)")
                    }
                    .disabled((creator.userId ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color(red: 0.1, green: 0.1, blue: 0.14))
                }
            }
        }
        .listStyle(.plain)
    }

    private func starCard(_ star: CreatorModel) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color.accentColor, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    CDNAsyncImage(url: URL(string: star.profilePicture ?? ""), targetSize: CGSize(width: 72, height: 72)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text("TR").font(.title.bold()).foregroundStyle(.white.opacity(0.6))
                    }
                    .clipShape(Circle())
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(star.firstname ?? "").font(.title3.bold()).foregroundStyle(.white)
                    Text("Score : \(formattedScore(star.score))").foregroundStyle(.yellow)
                }
                Spacer()
            }
            .padding(.vertical, 12).padding(.horizontal, 12)

            // Port de `fragment_creator.xml:95` (`android:text="👑 STAR"`) — emoji couronne, pas
            // juste "STAR" (vérifié dans le layout Android, pas deviné depuis la capture).
            Text("👑 STAR")
                .font(.caption2.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.14), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: 2))
    }

    private func rankRow(_ creator: CreatorModel, badge: String) -> some View {
        HStack(spacing: 12) {
            CDNAsyncImage(url: URL(string: creator.profilePicture ?? ""), targetSize: CGSize(width: 44, height: 44)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(red: 0.25, green: 0.25, blue: 0.3))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(creator.firstname ?? "").font(.body).foregroundStyle(.white)
                Text("Score: \(formattedScore(creator.score))").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(badge)
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.yellow, in: Capsule())
                .foregroundStyle(.black)
        }
    }

    private func formattedScore(_ score: Double) -> String {
        score == score.rounded() ? String(Int(score)) : String(score)
    }
}

@MainActor
final class CreatorOfWeekViewModel: ObservableObject {
    enum State {
        case loading
        case error
        case loaded(star: CreatorModel?, remaining: [CreatorModel])
    }

    @Published private(set) var state: State = .loading

    /// Port de `CreatorFragment.checkEmptyState` — le premier élément devient la "star", le reste
    /// (`remaining`, copie moins l'élément 0) alimente la liste classée.
    func load() async {
        state = .loading
        guard let creators = try? await TrophyRepository.shared.weeklyRank() else {
            state = .error
            return
        }
        guard let star = creators.first else {
            state = .loaded(star: nil, remaining: [])
            return
        }
        state = .loaded(star: star, remaining: Array(creators.dropFirst()))
    }
}
