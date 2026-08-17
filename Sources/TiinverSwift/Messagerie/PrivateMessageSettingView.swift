import SwiftUI

/// Port de `setting/SettingPrivateMessageFragmant.java` (238 lignes, lu en entier, 2026-08-18, P1)
/// — hébergé côté Android par `ProfileDetailActivity` (`messagerie/ui/ProfileDetailActivity.java`),
/// la MÊME Activity qui héberge `SettingGroupMessageFragmant` pour les groupes (déjà porté,
/// `GroupDetailView.swift`) selon `chatType`. Atteint en tapant le TITRE de la conversation
/// (`ActivityMsg.titleContainer.setOnClickListener`, `chatType.equals("chat")` branche vers cette
/// Activity) — même substitution que pour les groupes (`info.circle` en toolbar plutôt qu'un texte
/// de titre tapable, le titre natif de la barre de navigation SwiftUI n'étant pas directement
/// gestable). **Remplace le raccourci direct-vers-profil qui occupait ce bouton avant cette passe**
/// (`ChatView.swift`'s ancien commentaire documentait déjà ce gap comme "connu et volontairement
/// borné" — cet écran EST ce gap comblé), le raccourci profil devient une simple RANGÉE de cet écran
/// (`profile_btn`), fidèle à la hiérarchie réelle Android.
///
/// **100% local, AUCUN appel réseau dans le fichier Android source** (confirmé en le lisant en
/// entier — ni le switch de "livraison différée" ni le bouton bloquer n'appellent la moindre
/// méthode `TransportData`) : persistance `SharedPreferences` uniquement, reproduite via
/// `UserDefaults` (même motif que `ProfileViewModel.isBlocked`).
///
/// **Bouton "Bloquer" fidèlement REPRODUIT tel quel, PAS corrigé** : `mBlock.setOnClickListener`
/// côté Android ne fait QUE changer le texte du label en "Débloquer" — aucun appel réseau, aucune
/// lecture d'état au chargement, aucune persistance. Ce n'est PAS une simplification de portage :
/// c'est le comportement RÉEL du code source Android lui-même (probablement une fonctionnalité
/// commencée puis abandonnée côté client d'origine — le VRAI blocage réseau existe ailleurs,
/// `ProfileRepository.toggleBlock`/`UserProfile.block`, déjà porté et fonctionnel, voir
/// `ProfileViewModel.toggleBlock`). Reproduire un vrai blocage FONCTIONNEL ici serait inventer un
/// comportement qu'Android n'a jamais eu à cet endroit précis.
struct PrivateMessageSettingView: View {
    /// Port de `fullTitle`/`data.getTitle()` — texte affiché (nikname le plus souvent), DISTINCT de
    /// `username` ci-dessous (clé de persistance, le login réel) : Android utilise ces deux champs
    /// séparément (`toolbar.setTitle(title)` vs `Settings.getBooleanPreference(activity, username,
    /// …)`), pas interchangeables.
    let displayTitle: String
    /// Port de `username` (`i.getStringExtra("username")`, `data.getUsername()` — le LOGIN réel,
    /// PAS le nikname) — clé de persistance `SharedPreferences` exacte utilisée par Android pour ce
    /// switch/cette heure de livraison.
    let username: String
    let userId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var openProfile = false
    /// Port du texte du bouton bloquer — commence à "Bloquer" à CHAQUE ouverture (Android ne relit
    /// aucun état persisté ici non plus, voir note de tête de fichier).
    @State private var blockLabel = "Bloquer"

    /// Port de `Settings.getBooleanPreference(activity, username, true)` — clé = le NOM
    /// D'UTILISATEUR lui-même (pas un préfixe dédié, vérifié dans le fichier source), défaut `true`
    /// ("livraison instantanée" = interrupteur activé).
    @AppStorage private var deliverInstantly: Bool
    /// Port de `Settings.DELIVER_TIME_KEY+username` — chaîne libre formatée par `MyFragmentDialog`
    /// (type=4, sélecteur date+heure natif Android), ici un `DatePicker` SwiftUI natif à la place.
    @AppStorage private var deliverTimeRaw: String
    @State private var showDeliverTimePicker = false
    @State private var deliverTimeDraft = Date()

    init(displayTitle: String, username: String, userId: String?) {
        self.displayTitle = displayTitle
        self.username = username
        self.userId = userId
        _deliverInstantly = AppStorage(wrappedValue: true, username)
        _deliverTimeRaw = AppStorage(wrappedValue: "", "DELIVER_TIME_KEY" + username)
    }

    var body: some View {
        List {
            Section {
                Button {
                    openProfile = true
                } label: {
                    Label("Voir le profil", systemImage: "person.crop.circle")
                }
            }
            Section {
                Toggle("Livraison instantanée", isOn: $deliverInstantly) // R.id.deliverAtMoment
                if !deliverInstantly {
                    // Port de `mContainer2`/`mDeliverTimeView` — activé UNIQUEMENT quand
                    // l'interrupteur ci-dessus est désactivé (`setAlpha`/`setEnabled` fidèles).
                    Button {
                        deliverTimeDraft = Date()
                        showDeliverTimePicker = true
                    } label: {
                        HStack {
                            Text("Heure de livraison")
                            Spacer()
                            Text(deliverTimeRaw.isEmpty ? "Choisir" : deliverTimeRaw)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Quand désactivé, les messages sont livrés à l'heure choisie plutôt qu'immédiatement.")
            }
            Section {
                Button(role: .destructive) {
                    // Port EXACT de `mBlock.setOnClickListener` — voir note de tête de fichier.
                    blockLabel = "Débloquer"
                } label: {
                    Text(blockLabel)
                }
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fermer") { dismiss() }
            }
        }
        .sheet(isPresented: $showDeliverTimePicker) {
            NavigationStack {
                VStack {
                    DatePicker("Heure de livraison", selection: $deliverTimeDraft, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .padding()
                    Spacer()
                }
                .navigationTitle("Heure de livraison")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Port de `onDialogPositiveClick` — `mDeliverTimeView.setText(model.getText())`
                        // + persistance immédiate.
                        Button("OK") {
                            deliverTimeRaw = Self.formatter.string(from: deliverTimeDraft)
                            showDeliverTimePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Annuler") { showDeliverTimePicker = false }
                    }
                }
            }
        }
        // `navigationDestination(item:)` exige iOS 17 — même contournement que le reste du code base.
        .navigationDestination(isPresented: $openProfile) {
            if let userId {
                ProfileView(userId: userId, isCurrentUser: false)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
