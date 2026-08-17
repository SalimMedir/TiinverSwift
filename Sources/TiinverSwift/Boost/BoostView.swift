import SwiftUI

/// Port de `advertising/ui/BoostActivity.java` (entier, 2026-08-18, P1) — conteneur à 2 onglets
/// (`TabLayout`+`ViewPager2`, `BoostAdapter`) : "Créer" (`CreateBoostFragment`) et "Tableau de bord"
/// (`BoostDashboardFragment`). `showFragment(1)` (bascule vers le tableau de bord après succès de
/// création, `CreateBoostFragment`'s observer) reproduit via `selectedTab` lié.
struct BoostView: View {
    let activityId: Int

    @State private var selectedTab = 0
    private var userId: String { UserSession.shared.myId ?? "" }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CreateBoostView(userId: userId, activityId: activityId, onSubmitted: { selectedTab = 1 })
            }
            .tabItem { Label("Créer", systemImage: "megaphone") }
            .tag(0)

            NavigationStack {
                BoostDashboardView(userId: userId)
            }
            .tabItem { Label("Tableau de bord", systemImage: "chart.bar") }
            .tag(1)
        }
    }
}
