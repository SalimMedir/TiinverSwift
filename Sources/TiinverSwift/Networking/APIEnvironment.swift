import Foundation

/// URLs backend — reproduites à l'identique depuis `back_sync/infoContract.java`.
/// Le backend est hors périmètre du portage et reste inchangé (voir
/// TIINVER_IOS_PORT_ANALYSIS.md §6.1) : ne jamais modifier ces valeurs sans
/// modifier le serveur en parallèle.
enum APIEnvironment {
    /// infoContract.SERVER — API REST principale.
    static let restBaseURL = "https://tiinver.com/api/v1/"
    /// infoContract.VPS_SERVER — utilisé uniquement par TransportData.postToVPS(...).
    static let vpsBaseURL = "https://api.tiinver.com/api/v1/"
    /// infoContract.SERVERIO_URL — Socket.IO temps réel.
    static let socketURL = "https://api.tiinver.com:2020"
    /// infoContract.CDN_PHOTO_BASE_URL_V1
    static let cdnPhotoBaseURL = "https://cdn.tiinver.com/"
    /// infoContract.CDN_STREAM_BASE_URL_V1
    static let cdnStreamBaseURL = "https://stream.tiinver.com/"
}
