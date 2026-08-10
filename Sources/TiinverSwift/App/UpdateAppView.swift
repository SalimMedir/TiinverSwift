import SwiftUI

/// Port de `UpdateApp.java` — écran plein écran bloquant affiché quand
/// `FirebaseConfigManager.isNewUpdateEnabled()` est vrai ou que la date d'expiration configurée
/// est dépassée (voir `SplashActivity.navigateAfterConfig`, reproduit dans `RootRouterView.swift`).
struct UpdateAppView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app.fill").font(.system(size: 48))
            Text("Une nouvelle version est disponible").font(.headline)
            Button("Mettre à jour") {
                // Port de `infoContract.PLAYSTORE_LINK` — équivalent iOS pas encore disponible
                // (app non publiée sur l'App Store à ce stade). Placeholder à remplacer par le
                // vrai lien `https://apps.apple.com/app/idXXXXXXXXXX` une fois l'app publiée —
                // PAS fabriqué ici sans identifiant App Store réel.
                if let url = URL(string: "https://apps.apple.com/app/id0000000000") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
