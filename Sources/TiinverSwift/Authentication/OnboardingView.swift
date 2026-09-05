import SwiftUI

/// Port de `Authentification/onboarding/OnboardingFragment.java` + `ViewPagerAdapter.java`.
///
/// 5 pages, mêmes clés de ressources que l'original. **Images ajoutées (2026-08-30)** : les 5
/// visuels réels (`a1.webp`…`a4.webp`, `a5.png`, `res/drawable/`, référencés dans cet ordre exact
/// par `ViewPagerAdapter.java:26-30`) ont été récupérés depuis le dépôt Android, convertis en PNG
/// (aucun décodeur WebP natif côté Xcode/asset catalog) et ajoutés à `Assets.xcassets` sous
/// `Onboarding1`…`Onboarding5` (même ordre) — remplacent les `SF Symbols` provisoires utilisés
/// jusqu'ici en repli. Titres/descriptions `R.string.*` non lus — texte français provisoire dérivé
/// directement du NOM des clés de ressource Android, à remplacer par les véritables chaînes
/// localisées une fois `strings.xml` consulté.
struct OnboardingView: View {
    private struct Page {
        let imageName: String // Assets.xcassets — voir commentaire de tête (Onboarding1…5)
        let title: String // clé R.string.* d'origine en commentaire
        let description: String
    }

    private let pages: [Page] = [
        Page(imageName: "Onboarding1", // a1.webp
             title: "Publiez votre contenu", // R.string.publication_title
             description: "Partagez photos et vidéos avec votre communauté."), // R.string.publication_desc
        Page(imageName: "Onboarding2", // a2.webp
             title: "Discutez", // R.string.chat_title
             description: "Échangez en messages privés ou en groupe."), // R.string.chat_desc
        Page(imageName: "Onboarding3", // a3.webp
             title: "Groupes lucratifs", // R.string.group / R.string.group_lucratif_des
             description: "Rejoignez ou créez des groupes rémunérateurs."),
        Page(imageName: "Onboarding4", // a4.webp
             title: "Messages programmés", // R.string.schedule_message_title
             description: "Planifiez l'envoi de vos messages."), // R.string.schedule_message_desc
        Page(imageName: "Onboarding5", // a5.png
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
                        Image(pages[index].imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
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
                    Button(NSLocalizedString("auth_previous", comment: "Bouton précédent onboarding")) { currentPage -= 1 } // backbtn
                }
                Spacer()
                Button(NSLocalizedString("auth_skip", comment: "Bouton passer onboarding"), action: onFinished) // skipbtn → position 2
                Spacer()
                Button(currentPage < pages.count - 1
                    ? NSLocalizedString("auth_next", comment: "Bouton suivant onboarding")
                    : NSLocalizedString("auth_finish", comment: "Bouton terminer onboarding")) { // nextbtn
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
