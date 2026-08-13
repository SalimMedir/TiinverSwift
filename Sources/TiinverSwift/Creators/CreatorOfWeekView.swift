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
struct CreatorOfWeekView: View {
    @StateObject private var viewModel = CreatorOfWeekViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
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
        .navigationTitle("Classement")
        .task { await viewModel.load() }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text("Impossible de charger le classement").foregroundStyle(.secondary)
            Button("Réessayer") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Aucun créateur classé cette semaine").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(star: CreatorModel, remaining: [CreatorModel]) -> some View {
        List {
            Section {
                NavigationLink {
                    ProfileView(userId: star.userId ?? "", isCurrentUser: false)
                } label: {
                    starCard(star)
                }
            }
            Section {
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, creator in
                    NavigationLink {
                        ProfileView(userId: creator.userId ?? "", isCurrentUser: false)
                    } label: {
                        rankRow(creator, badge: "TOP \(index + 1)")
                    }
                }
            }
        }
    }

    private func starCard(_ star: CreatorModel) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: star.profilePicture ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.yellow)
                    .background(Circle().fill(.white))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(star.firstname ?? "").font(.title3.bold())
                Text("Score : \(formattedScore(star.score))").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func rankRow(_ creator: CreatorModel, badge: String) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: creator.profilePicture ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(creator.firstname ?? "").font(.body)
                Text("Score: \(formattedScore(creator.score))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
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
