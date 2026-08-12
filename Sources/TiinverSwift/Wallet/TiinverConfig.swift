import Foundation

/// Port de `com.tiinver.TiinverConfig` (89 lignes, lu en entier) — zone tarifaire/devise dérivée du
/// pays de l'utilisateur, condition toutes les vues Wallet (`ZONE=="CEMAC"` → FCFA/mobile money,
/// sinon → USDC/crypto).
///
/// **Détection de pays SIMPLIFIÉE par rapport à Android, documentée** : `CountryManager.java`
/// (48 lignes, lu en entier) essaie D'ABORD `TelephonyManager.getSimCountryIso()`/
/// `getNetworkCountryIso()`, puis se rabat sur `Locale.getDefault().getCountry()`. Côté iOS,
/// `CoreTelephony`/`CTCarrier` (l'équivalent le plus proche) est **restreint par Apple depuis
/// iOS 16 pour raisons de confidentialité** (`CTCarrier` retourne des valeurs génériques/vides sur
/// device réel depuis iOS 16, information publique et bien documentée, pas une supposition) — le
/// porter fidèlement produirait un code mort qui semble fonctionner mais ne renvoie jamais de vraie
/// valeur. Utilise directement `Locale.current.region` (équivalent exact du repli Android
/// `Locale.getDefault().getCountry()`), qui était de toute façon le dernier recours réel.
enum TiinverZone: String {
    case cemac = "CEMAC"
    case other = "OTHER"
}

enum TiinverConfig {
    private(set) static var zone: TiinverZone = .other
    private(set) static var currency: String = "USDC"
    private(set) static var countryName: String = "Global"
    private(set) static var withdrawMethod: String = "Crypto"
    private(set) static var iso: String = "OTHER"

    /// Port de `TiinverConfig.init(Context)` — à appeler une fois au démarrage (voir `AppDelegate`).
    static func configure() {
        let country = Locale.current.region?.identifier.uppercased() ?? "UNKNOWN"
        switch country {
        case "TD": setCemac(name: "Tchad"); withdrawMethod = "Airtel Money / Moov Money"; iso = "TD"
        case "CM": setCemac(name: "Cameroun"); withdrawMethod = "MTN Mobile Money / Orange Money"; iso = "CM"
        case "CF": setCemac(name: "Centrafrique"); withdrawMethod = "Orange Money / Moov Money"; iso = "CF"
        case "CG": setCemac(name: "Congo"); withdrawMethod = "Airtel Money / MTN Money"; iso = "CG"
        case "GA": setCemac(name: "Gabon"); withdrawMethod = "Airtel Money / Moov Money"; iso = "GA"
        case "GQ": setCemac(name: "Guinée équatoriale"); withdrawMethod = "GIMAC Pay / Mobile Money"; iso = "GQ"
        default:
            zone = .other
            currency = "USDC"
            countryName = "Global"
            withdrawMethod = "Crypto"
            iso = "OTHER"
        }
    }

    /// Port de `TiinverConfig.setCurrency(String)` — appelé par les écrans wallet quand
    /// l'utilisateur bascule manuellement entre un opérateur mobile money et "Crypto (USDC)".
    static func setCurrency(_ value: String) { currency = value }

    private static func setCemac(name: String) {
        zone = .cemac
        currency = "FCFA"
        countryName = name
    }
}

/// Port de `models/Country.java`/`CountryData.java` (`loadCountries`, asset `countries.json` non
/// disponible pour ce portage — jamais lu, contenu de ressource pas de code) — reconstruit à partir
/// des 6 pays CEMAC déjà énumérés dans `TiinverConfig.java` lui-même, avec leurs indicatifs
/// téléphoniques E.164 réels (faits publics standardisés, pas une supposition métier). Toujours
/// terminé par "Autres pays" (`isoCode == "others"`), comme l'original.
struct WalletCountry: Identifiable, Hashable {
    let id: String // isoCode
    let name: String
    let phoneCode: String

    static let cemac: [WalletCountry] = [
        WalletCountry(id: "TD", name: "Tchad", phoneCode: "+235"),
        WalletCountry(id: "CM", name: "Cameroun", phoneCode: "+237"),
        WalletCountry(id: "CF", name: "Centrafrique", phoneCode: "+236"),
        WalletCountry(id: "CG", name: "Congo", phoneCode: "+242"),
        WalletCountry(id: "GA", name: "Gabon", phoneCode: "+241"),
        WalletCountry(id: "GQ", name: "Guinée équatoriale", phoneCode: "+240"),
    ]
    static let others = WalletCountry(id: "others", name: "Autres pays", phoneCode: "+000") // R.string.others_countries

    /// Port de `CountryData.loadCountries` — liste complète pour la zone active.
    static var forCurrentZone: [WalletCountry] {
        TiinverConfig.zone == .cemac ? cemac + [others] : [others]
    }
}
