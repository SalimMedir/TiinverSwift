import FirebaseRemoteConfig

/// Port de `setting/FirebaseConfigManager.java` — SDK iOS officiel, portage direct comme
/// annoncé dans TIINVER_IOS_PORT_ANALYSIS.md ("Firebase Remote Config iOS SDK est un portage
/// direct, même service, SDK iOS officiel").
///
/// Les valeurs par défaut de `res/xml/remote_config_defaults.xml` (fichier de RESSOURCES, pas de
/// code — jamais lu, contenu non disponible pour ce portage) doivent être reproduites dans un
/// plist iOS équivalent (`RemoteConfigDefaults.plist`) par l'utilisateur/l'équipe produit avant le
/// premier build réel — PAS fabriquées ici sans source. `setDefaults(fromPlist:)` référence ce
/// nom de fichier ; le plist lui-même n'est pas créé par ce portage.
final class TiinverFirebaseConfigManager {
    static let shared = TiinverFirebaseConfigManager()

    private let remoteConfig: RemoteConfig

    private init() {
        remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1h, comme l'original
        remoteConfig.configSettings = settings
        // Voir note en tête de fichier : RemoteConfigDefaults.plist doit être fourni séparément,
        // reproduction de res/xml/remote_config_defaults.xml (contenu jamais lu).
        remoteConfig.setDefaults(fromPlist: "RemoteConfigDefaults")
    }

    func fetchAndActivate() async -> Bool {
        (try? await remoteConfig.fetchAndActivate()) != nil
    }

    var minimumWithdrawalAmount: Double { remoteConfig["minimum_withdrawal_amount"].numberValue.doubleValue }
    var coinsValue: Double { remoteConfig["coins_value"].numberValue.doubleValue }
    var coinsValueInDollar: Double { remoteConfig["coins_value_dollar"].numberValue.doubleValue }
    var animemesMixMaxDuration: Int64 { remoteConfig["animemes_Mix_Max_Duration"].numberValue.int64Value }
    var transactionFeePercent: Double { remoteConfig["transaction_fee_percent"].numberValue.doubleValue }
    var adsRewardAsGems: Bool { remoteConfig["ads_reward_as_gems"].boolValue }
    var certificationPrice: Double { remoteConfig["certification_price"].numberValue.doubleValue }
    var welcomeMessage: String { remoteConfig["welcome_message"].stringValue ?? "" }
    var maxVideoDuration: Int64 { remoteConfig["max_video_duration"].numberValue.int64Value }
    var isAdsEnabledOnFeed: Bool { remoteConfig["ads_feed_enabled"].boolValue }
    var isRewardedFromAnimemesCreation: Bool { remoteConfig["create_animemes_be_rewarded"].boolValue }
    var isAdsRewardedEnabled: Bool { remoteConfig["ads_rewarded_enabled"].boolValue }
    var rewardDividedBy: Double { remoteConfig["reward_divided_by"].numberValue.doubleValue }
    var cdnBaseUrl: String { remoteConfig["cdn_base_url"].stringValue ?? "" }
    var streamBaseUrl: String { remoteConfig["stream_base_url"].stringValue ?? "" }
    var isNewUpdateEnabled: Bool { remoteConfig["new_update_enabled"].boolValue }
    var isAnimemesPremiumEnabled: Bool { remoteConfig["animemes_premium_enabled"].boolValue }
    var expireDay: Int { Int(remoteConfig["app_expire_day"].numberValue.doubleValue) }
    var expireMonth: Int { Int(remoteConfig["app_expire_month"].numberValue.doubleValue) }
    var expireYear: Int { Int(remoteConfig["app_expire_year"].numberValue.doubleValue) }
    var allowGiftCommenter: Bool { remoteConfig["allow_gift_commenter"].boolValue }
    var allowChatSendReceiveSound: Bool { remoteConfig["allow_chat_send_receive_sound"].boolValue }
    var versionCode: Int { Int(remoteConfig["version_code"].numberValue.doubleValue) }

    /// `TiinverConfig.ISO`/`CountryManager` (pays de l'utilisateur, variantes `_TD`/`_CM`/etc. —
    /// voir TIINVER_IOS_PORT_ANALYSIS.md ligne AdMob) PAS encore portés (module 16, AdMob/pays).
    /// `adsRewardedReward()`/`adsOnFeedReward()` de l'original (qui dépendent de `TiinverConfig.ISO`)
    /// sont donc différées à ce module plutôt que déclarées avec un pays codé en dur par défaut.
}
