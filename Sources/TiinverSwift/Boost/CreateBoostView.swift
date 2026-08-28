import SwiftUI

/// Port de `advertising/ui/CreateBoostFragment.java` (497 lignes, entier, 2026-08-18, P1) — formulaire
/// de création d'une campagne Boost pour un post donné.
///
/// **Substitutions d'UI documentées, pas des simplifications de comportement** :
/// - `RangeSlider` (Material, double-poignée) pour la tranche d'âge → 2 `Slider` SwiftUI liés
///   (min borné à `≤ max`) : SwiftUI n'a pas d'équivalent natif iOS 16 sans dépendance tierce,
///   même contournement de principe que la `.page` TabView pivotée pour le pager vertical du Feed.
/// - `Spinner` (placement, devise) → `Picker` natif SwiftUI, même sémantique.
/// - Icônes crayon `budgetEdit`/`durationEdit` (boîte de dialogue de saisie manuelle) → `TextField`
///   numérique directement à côté du slider, même fonctionnalité (saisie précise), sans dialogue
///   modal séparé.
struct CreateBoostView: View {
    let userId: String
    let activityId: Int
    var onSubmitted: () -> Void = {}

    @State private var budget: Double = 100
    @State private var duration: Double = 1
    /// **Corrigé (2026-08-28, V7-F-012)** — `"views"`, PAS `"likes"`. `getSelectedObjectif()`
    /// (`CreateBoostFragment.java:338-343`) a bien un repli textuel `"likes"`, mais il n'est en
    /// pratique JAMAIS atteint côté Android : `fragment_create_boost.xml:50-55` pré-coche
    /// `radioView` (`android:checked="true"`), donc le vrai défaut observable — celui qu'un
    /// utilisateur obtient en ne touchant pas le sélecteur — est "views". Cette confusion entre le
    /// repli de code et le défaut RÉEL avait aussi faussé l'estimation initiale affichée
    /// (`budget/3 likes` au lieu de `budget*4 vues`) et, en cas de soumission sans interaction, la
    /// valeur `objectif`/`dailyLimit` réellement envoyée au serveur.
    @State private var objective = "views"
    @State private var placement = "Feed"
    @State private var gender = "Tous"
    @State private var minAge: Double = 18
    @State private var maxAge: Double = 55
    @State private var countryQuery = ""
    @State private var countrySuggestions: [TagModel] = []
    @State private var selectedCountries: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var useGems = false
    @State private var isSubmitting = false
    @State private var submitMessage: String?
    @State private var submitSucceeded = false
    @State private var showInsufficientBalance = false

    private static let maxBudget: Double = 250_000
    private static let maxDuration: Double = 30

    private var currentBalance: Double { useGems ? UserSession.shared.gemsAmount : UserSession.shared.coinsAmount }
    private var currency: String { useGems ? "gemmes" : "pièces" }

    /// Port de `estimateReach` — formules EXACTES (division entière fidèle via `Int`).
    private func estimateReach(objective: String, budgetPieces: Int) -> Int {
        let pieces = max(0, budgetPieces)
        switch objective {
        case "views": return pieces * 4
        case "likes": return pieces / 3
        case "followers": return pieces / 5
        default: return 0
        }
    }

    private var budgetInt: Int { Int(budget) }
    private var durationInt: Int { Int(duration) }
    private var dailyEstimate: Int { estimateReach(objective: objective, budgetPieces: budgetInt) }
    private var objectiveTarget: Int { durationInt * dailyEstimate }
    private var totalCost: Int { budgetInt * durationInt }

    var body: some View {
        Form {
            Section("Solde") {
                Picker("Devise", selection: $useGems) {
                    Text("Pièces").tag(false)
                    Text("Gemmes").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Solde actuel : \(currentBalance, specifier: "%.0f") \(currency)")
                    .foregroundStyle(.secondary)
            }

            Section("Budget & durée") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Budget")
                        Spacer()
                        TextField("", value: $budget, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(currency)
                    }
                    Slider(value: $budget, in: 5...Self.maxBudget)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Durée")
                        Spacer()
                        TextField("", value: $duration, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("jours")
                    }
                    Slider(value: $duration, in: 1...Self.maxDuration)
                }
                Text("Total : \(totalCost) \(currency)")
                Text("Estimation par jour : \(dailyEstimate) \(objective)")
                    .foregroundStyle(.secondary)
            }

            Section("Objectif") {
                Picker("Objectif", selection: $objective) {
                    Text("Vues").tag("views")
                    Text("J'aime").tag("likes")
                    Text("Abonnés").tag("followers")
                }
                .pickerStyle(.segmented)
                Picker("Emplacement", selection: $placement) {
                    Text("Feed").tag("Feed")
                    Text("Écran de démarrage").tag("Splash Screen")
                }
            }

            Section("Audience") {
                Picker("Genre", selection: $gender) {
                    Text("Tous").tag("Tous")
                    Text("Homme").tag("Homme")
                    Text("Femme").tag("Femme")
                }
                VStack(alignment: .leading) {
                    Text("Âge : \(Int(minAge)) - \(maxAge >= 55 ? "55+" : "\(Int(maxAge))") ans")
                    // **Corrigé (2026-08-28, V7-F-013)** — borne basse alignée sur le `RangeSlider`
                    // Android (`fragment_create_boost.xml:174-191`, `valueFrom="18"`) : la valeur
                    // `13` permettait de soumettre un ciblage publicitaire `age_min` structurellement
                    // impossible à produire côté Android, risque de conformité (ciblage de mineurs).
                    Slider(value: $minAge, in: 18...maxAge, step: 1) { Text("Âge min") }
                    Slider(value: $maxAge, in: minAge...55, step: 1) { Text("Âge max") }
                }
                countryPicker
            }

            Section {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Lancer le boost").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || budgetInt < 5)
                if let submitMessage {
                    Text(submitMessage).foregroundStyle(submitSucceeded ? .green : .red)
                }
            }
        }
        .navigationTitle("Créer un boost")
        // Port du dialogue `FireMissilesDialogFragment` (solde insuffisant) — `setupSubmit()`.
        .alert("Solde insuffisant", isPresented: $showInsufficientBalance) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Votre solde ne couvre pas le coût total de ce boost.")
        }
    }

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !selectedCountries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedCountries, id: \.self) { country in
                            HStack(spacing: 4) {
                                Text(country)
                                Button { selectedCountries.removeAll { $0 == country } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }
                }
            }
            TextField("Ajouter un pays", text: $countryQuery)
                .onChange(of: countryQuery) { _ in scheduleCountrySearch() }
            if !countrySuggestions.isEmpty {
                ForEach(countrySuggestions) { suggestion in
                    Button {
                        if let tag = suggestion.tag, !selectedCountries.contains(tag) {
                            selectedCountries.append(tag)
                        }
                        countryQuery = ""
                        countrySuggestions = []
                    } label: {
                        Text(suggestion.tag ?? "")
                    }
                }
            }
        }
    }

    /// Port de `countryTagInput.setTextChangedListener` → `getSugestionFromServeur("country", s)`.
    private func scheduleCountrySearch() {
        searchTask?.cancel()
        let q = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { countrySuggestions = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? await AdsRepository.shared.searchTags(key: "country", query: q)) ?? []
            // **Corrigé (2026-08-28, V7-F-026)** — `Task.isCancelled` n'était vérifié qu'AVANT
            // l'appel réseau, pas après : une réponse lente pour une frappe ancienne pouvait
            // arriver après une réponse plus récente et l'écraser. Même garde re-vérifiée après
            // l'appel réseau déjà appliquée ailleurs dans ce projet pour ce même motif
            // (`ChatSearchView.swift`, `NewMessageView.swift`, `SearchView.swift`/V6-F-012).
            guard !Task.isCancelled else { return }
            countrySuggestions = results
        }
    }

    /// Port de `getSelectedText(genderGroup)`.
    private var genderCodes: [String] {
        switch gender {
        case "Homme": return ["M"]
        case "Femme": return ["F"]
        default: return ["M", "F"]
        }
    }

    /// Port de `setupSubmit()` — garde budget<5 SILENCIEUSE (Android : `return;` sans message,
    /// reproduit tel quel via `.disabled` ci-dessus plutôt qu'un tap sans effet).
    private func submit() {
        guard budgetInt >= 5 else { return }
        guard Double(totalCost) <= currentBalance else {
            showInsufficientBalance = true
            return
        }
        isSubmitting = true
        submitMessage = nil
        let audience = Audience(country: selectedCountries, gender: genderCodes, age_min: String(Int(minAge)), age_max: String(Int(maxAge)))
        let request = AdsRepository.BoostRequest(
            userId: userId, activityId: activityId, objective: objective, objectiveTarget: objectiveTarget,
            budgetPoints: totalCost, durationDays: durationInt, placement: placement, dailyLimit: dailyEstimate,
            audience: audience
        )
        Task {
            do {
                try await AdsRepository.shared.createBoost(request, useGems: useGems)
                // **Corrigé (2026-08-28, V6-F-016)** — déduction LOCALE optimiste sur le BON solde
                // selon `useGems`. Android écrit TOUJOURS dans `COINS_AMOUNT`, même payé en gemmes
                // (`Settings.setFloatPreference(..., COINS_AMOUNT, ...)` inconditionnel côté
                // `CreateBoostFragment.java:208-215`) — bug partagé confirmé par l'audit, mais le
                // correctif est autonome (ne dépend d'aucun changement Android) et purement
                // défensif financièrement : sans lui, un achat payé en gemmes décrémentait à tort
                // le solde de PIÈCES mis en cache localement (`coinsAmount`), tout en laissant le
                // vrai solde de gemmes localement inchangé jusqu'à la prochaine resynchronisation
                // serveur — un affichage local durablement faux sur les DEUX soldes à la fois.
                if useGems {
                    UserSession.shared.gemsAmount = currentBalance - Double(totalCost)
                } else {
                    UserSession.shared.coinsAmount = currentBalance - Double(totalCost)
                }
                isSubmitting = false
                submitSucceeded = true
                submitMessage = "Envoyé avec succès"
                onSubmitted()
            } catch {
                isSubmitting = false
                submitSucceeded = false
                submitMessage = "Oups, une erreur est survenue"
            }
        }
    }
}
