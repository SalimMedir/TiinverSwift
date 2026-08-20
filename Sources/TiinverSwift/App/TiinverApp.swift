import SwiftUI

@main
struct TiinverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Port de `ThemeUtils.applyTheme(Context)` (`BaseActivity.java:24`, appelé AVANT `super.onCreate()`
    /// sur CHAQUE Activity — donc l'app entière, à chaque écran) — **ajouté le 2026-08-20,
    /// MIGRATION_PARITY_AUDIT_V3.md V3-F-131, Phase B P0**. `SettingAppearanceView` (module Réglages)
    /// écrit déjà `@AppStorage("theme")` (`"Light"`/`"Dark"`, mêmes 2 valeurs que
    /// `ThemeUtils`/`SettingChatFragment.java:142,145` — Android n'a PAS de 3ᵉ état "Système",
    /// confirmé par lecture de `ThemeUtils.java` : seuls `MODE_NIGHT_YES`/`MODE_NIGHT_NO`) mais RIEN
    /// ne la consommait jamais — confirmé par grep exhaustif avant ce correctif, le bascule n'avait
    /// aucun effet visuel. `.preferredColorScheme` appliqué ICI, à la racine de `WindowGroup`, cascade
    /// à toute la hiérarchie de vues — équivalent fonctionnel de l'application par `BaseActivity` sur
    /// CHAQUE écran, sans avoir besoin de le répéter vue par vue.
    @AppStorage("theme") private var theme = "Light"

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .preferredColorScheme(theme == "Dark" ? .dark : .light)
        }
    }
}
