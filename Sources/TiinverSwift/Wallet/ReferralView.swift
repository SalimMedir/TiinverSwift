import CoreImage.CIFilterBuiltins
import SwiftUI

/// Port de `ReferralActivity.java` (511 lignes, lu en entier) — lien de parrainage, QR code, compteur
/// de filleuls, accès à `EarnCoinsView` (pub rewarded).
///
/// **Non porté, délibérément simplifié, documenté** : génération d'une "carte" QR téléchargeable
/// avec dégradé/ombre portée dessinée à la main (`generateQrCard`, ~150 lignes de `Canvas`/`Paint`
/// Android) — décoratif, remplacé par un simple QR code + bouton de partage natif
/// (`ShareLink`/`UIActivityViewController`) ; carrousel de publicités natives (`AdLoader`/
/// `NativeAd`, `CustomAdsView`) différé au module 16 (AdMob).
struct ReferralView: View {
    @State private var referralTotal = 0
    private let referralCode = UserSession.shared.referralCode ?? ""
    private var link: String { "https://tiinver.com/invite.php?code=\(referralCode)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                    .frame(height: 50)

                Text("Regardez des publicités dans votre fil et gagnez entre 1 et 2 pièces") // R.string.watch_ads_in_your_news_feed_and_earn_between_x_to_y_coins
                    .font(.subheadline).multilineTextAlignment(.center)

                NavigationLink("Regarder une vidéo") { EarnCoinsView(adProvider: RewardedAdManager()) } // R.id.btn_watch_video
                    .buttonStyle(.borderedProminent)

                if let qrImage = Self.qrCode(from: link) {
                    Image(uiImage: qrImage).interpolation(.none).resizable().frame(width: 200, height: 200)
                }

                Text("Code de parrainage : \(referralCode)") // R.string.referral_code_label
                    .font(.headline)
                Text(link).font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button("Copier le lien") { UIPasteboard.general.string = link } // R.id.copy_link
                    ShareLink(item: URL(string: link) ?? URL(string: "https://tiinver.com")!) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)

                VStack {
                    Text("\(referralTotal)").font(.largeTitle.bold())
                    Text(referralLabel).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Parrainage")
        .task { await loadReferralTotal() }
    }

    /// Port de `updateReferralCountUI` — 3 formes grammaticales selon le total (0/1/plusieurs).
    private var referralLabel: String {
        switch referralTotal {
        case 0: return "Aucun filleul pour l'instant" // R.string.no_referral_yet
        case 1: return "ami parrainé" // R.string.referral_friend_singular
        default: return "amis parrainés" // R.string.referral_friend_plural
        }
    }

    private func loadReferralTotal() async {
        guard let userId = UserSession.shared.myId else { return }
        referralTotal = (try? await WalletRepository.shared.referralTotal(userId: userId)) ?? 0
    }

    /// Port de `generateQrBitmap` (ZXing) — remplacé par `CIFilter.qrCodeGenerator`, générateur QR
    /// natif Core Image, API système bien établie (pas de dépendance tierce à vérifier, contrairement
    /// à ZXing côté Android).
    private static func qrCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
