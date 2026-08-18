import SwiftUI

/// Port de `Activity/ui/StatisticsActivity.java` (228 lignes, entier, 2026-08-18, P2) — statistiques
/// d'un post (`statisticBtn`, visible UNIQUEMENT pour ses propres posts, `view/CustomCardView.java:
/// 238-243`, même garde que `promoteBtn` déjà câblé pour Boost).
struct StatisticsView: View {
    let activityId: Int

    @State private var stats: StatisticModel?
    @State private var isLoading = true

    private var userId: String { UserSession.shared.myId ?? "" }

    var body: some View {
        List {
            if let stats {
                Section("Engagement") {
                    row("Vues", "\(stats.views ?? 0)")
                    row("J'aime", "\(stats.likes ?? 0)")
                    row("Partages", "\(stats.shares ?? 0)")
                    row("Commentaires", "\(stats.comments ?? 0)")
                }
                Section("Vidéo") {
                    row("Vues vidéo", "\(stats.views ?? 0)")
                    row("Temps de visionnage total", "\(stats.total_watch_time ?? 0)")
                    row("Temps de visionnage moyen", "\(stats.avg_watch_time ?? 0)")
                    row("Taux de complétion", "\(stats.completion_rate ?? 0)")
                }
                Section("Abonnés") {
                    row("Nouveaux abonnés", "\(stats.followers_period ?? 0)")
                    row("Abonnés totaux", "\(stats.followers_total ?? 0)")
                    row("Revenu (pièces)", "\(stats.revenu_coins ?? 0)")
                }
                Section("Audience") {
                    // Port EXACT de la boucle `for (Map.Entry<...> entry : genderDist.entrySet())`
                    // — voir `Self.lastMatchingBucket` : bug Android reproduit fidèlement, PAS
                    // corrigé (chaque itération écrase LES 3 variables, la dernière entrée du Map
                    // "gagne" pour son propre champ et remet les 2 autres à "--").
                    let gender = Self.lastMatchingBucket(stats.gender_distribution, keys: ["M", "F", "unknow"])
                    row("Hommes", gender["M"] ?? "--")
                    row("Femmes", gender["F"] ?? "--")
                    row("Non précisé", gender["unknow"] ?? "--")

                    let age = Self.lastMatchingBucket(stats.age_distribution, keys: ["18-24", "25_34", "35_44", "45_54", "55+", "unknown"])
                    row("18-24 ans", age["18-24"] ?? "--")
                    row("25-34 ans", age["25_34"] ?? "--")
                    row("35-44 ans", age["35_44"] ?? "--")
                    row("45-54 ans", age["45_54"] ?? "--")
                    row("55 ans et +", age["55+"] ?? "--")
                    row("Âge non précisé", age["unknown"] ?? "--")
                }
                if let countries = stats.country_distribution, !countries.isEmpty {
                    Section("Pays") {
                        ForEach(countries.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                            row(entry.key, "\(entry.value)")
                        }
                    }
                }
                if let cities = stats.city_distribution, !cities.isEmpty {
                    Section("Villes") {
                        ForEach(cities.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                            row(entry.key, "\(entry.value)")
                        }
                    }
                }
                // Port du bouton `promote` — même destination que `promoteBtn` (Boost).
                Section {
                    NavigationLink {
                        BoostView(activityId: activityId)
                    } label: {
                        Text("Promouvoir ce post").frame(maxWidth: .infinity)
                    }
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle("Statistiques")
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    /// Port EXACT de la boucle Android : pour chaque clé surveillée, seule la valeur de la
    /// DERNIÈRE entrée du dictionnaire dont la clé matche cette clé précise est conservée — un
    /// dictionnaire avec plusieurs entrées ne peut peupler qu'UN SEUL champ à la fois par
    /// construction de la boucle d'origine (`manStr`/`womanStr`/`unknowStr` réaffectés à CHAQUE
    /// itération, pas seulement pour la clé courante). Comportement observé, PAS corrigé — un
    /// dictionnaire re-trié/mappé "proprement" ici afficherait des données qu'Android lui-même
    /// n'affiche jamais dans la pratique.
    private static func lastMatchingBucket(_ dict: [String: Int]?, keys: [String]) -> [String: String] {
        guard let dict, !dict.isEmpty else { return [:] }
        var result: [String: String] = [:]
        // L'ordre d'itération d'un `Dictionary` Swift n'est pas garanti stable non plus qu'un
        // `LinkedTreeMap` Gson — reproduit la meilleure approximation disponible (dernière entrée
        // rencontrée dans l'ordre de decodage JSON, via `sorted` sur les clés d'origine JSON quand
        // disponible n'est pas possible ici ; on ne peut viser que la MÊME classe de résultat
        // dégénéré, pas un ordre bit-à-bit identique, JSONDecoder ne préservant pas non plus l'ordre).
        for (key, value) in dict {
            for candidate in keys {
                result[candidate] = (key == candidate) ? String(value) : "--"
            }
        }
        return result
    }

    private func load() async {
        isLoading = true
        stats = try? await AdsRepository.shared.fetchStatistics(activityId: activityId, userId: userId)
        isLoading = false
    }
}
