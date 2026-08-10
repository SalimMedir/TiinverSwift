import SwiftUI

/// Port de `Authentification/onboarding/OnboardingFragment.java` + `ViewPagerAdapter.java`.
///
/// 5 pages, mêmes clés de ressources que l'original (images `a1`-`a5` non disponibles — remplacées
/// par des `SF Symbols` provisoires ; titres/descriptions `R.string.*` non lus — texte français
/// provisoire dérivé directement du NOM des clés de ressource Android, à remplacer par les
/// véritables chaînes localisées une fois `strings.xml` consulté).
struct OnboardingView: View {
    private struct Page {
        let symbol: String
        let title: String // clé R.string.* d'origine en commentaire
        let description: String
    }

    private let pages: [Page] = [
        Page(symbol: "photo.on.rectangle.angled",
             title: "Publiez votre contenu", // R.string.publication_title
             description: "Partagez photos et vidéos avec votre communauté."), // R.string.publication_desc
        Page(symbol: "bubble.left.and.bubble.right.fill",
             title: "Discutez", // R.string.chat_title
             description: "Échangez en messages privés ou en groupe."), // R.string.chat_desc
        Page(symbol: "person.3.fill",
             title: "Groupes lucratifs", // R.string.group / R.string.group_lucratif_des
             description: "Rejoignez ou créez des groupes rémunérateurs."),
        Page(symbol: "clock.badge",
             title: "Messages programmés", // R.string.schedule_message_title
             description: "Planifiez l'envoi de vos messages."), // R.string.schedule_message_desc
        Page(symbol: "dollarsign.circle.fill",
             title: "Compte de monétisation", // R.string.monetization_account
             description: "Gagnez de l'argent grâce à votre contenu.") // R.string.monetization_account_desc
    ]

    @State private var currentPage = 0
    var onFinished: () -> Void

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Image(systemName: pages[index].symbol)
                            .font(.system(size: 80))
                        Text(pages[index].title).font(.title2.bold())
                        Text(pages[index].description).multilineTextAlignment(.center)
                    }
                    .padding()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                if currentPage > 0 {
                    Button("Précédent") { currentPage -= 1 } // backbtn
                }
                Spacer()
                Button("Passer", action: onFinished) // skipbtn → position 2
                Spacer()
                Button(currentPage < pages.count - 1 ? "Suivant" : "Terminer") { // nextbtn
                    if currentPage < pages.count - 1 {
                        currentPage += 1
                    } else {
                        onFinished() // → position 2 (SignUpWithGoogle)
                    }
                }
            }
            .padding()
        }
    }
}
