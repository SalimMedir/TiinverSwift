import SwiftUI

/// Port de `feed_header_layout.xml`'s `<include layout="@layout/free_coins_win_banner"/>`
/// (`layout-v21/free_coins_win_banner.xml`, lu en entier) + `ActivityAdapter.HeaderViewHolder.
/// btn_start_earn` (`Intent(v.getContext(), ReferralActivity.class)`) — bannière PROMOTIONNELLE
/// Tiinver ("Gagnez des pièces gratuites"/`R.string.win_free_coins`), distincte de la bannière
/// publicitaire tierce AdMob affichée juste au-dessus dans `FeedView.homeHeader`.
struct WinFreeCoinsBannerView: View {
    @State private var showReferral = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // `@string/win_free_coins` / `@string/start_earning_free_coins_by_watching_videos_or_sharing_your_referral_link`
                Text("Gagnez des pièces gratuites")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Commencez à gagner des pièces gratuites en regardant des vidéos ou en partageant votre lien de parrainage")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 8)
            // `@string/get_started`
            Button("Commencer") { showReferral = true }
                .font(.caption.bold())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white, in: Capsule())
                .foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.75))
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(red: 0.55, green: 0.15, blue: 0.75), Color(red: 0.85, green: 0.25, blue: 0.55)],
                            startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.horizontal, 12)
        .sheet(isPresented: $showReferral) {
            NavigationStack { ReferralView() }
        }
    }
}
