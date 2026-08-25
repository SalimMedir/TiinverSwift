import Foundation

/// Port de `wallet/WalletRepository.java` (364 lignes, lu en entier) — couche REST du portefeuille
/// virtuel (solde, historique, retrait, transfert, conversion, parrainage), backend PHP INCHANGÉ
/// (voir TIINVER_IOS_PORT_ANALYSIS.md §6.1). Les endpoints/formats de payload sont recopiés à
/// l'identique — seule la couche transport change (`APIClient`/`URLSession` au lieu de
/// `TransportData`/Volley).
///
/// **`submitPurchasseRequest`/`submitPurchasseByCrypto` (endpoints `purchaserequests`/
/// `crypto/check-transaction`) DÉLIBÉRÉMENT PAS PORTÉS** — c'était le flux d'ACHAT réel
/// (mobile money/crypto avec ID de transaction saisi à la main), remplacé côté iOS par StoreKit 2
/// (`CoinStoreManager.swift`) sur demande explicite. Voir la section "Audit conformité App Store —
/// Wallet/Paiements" de MIGRATION_PROGRESS.md pour le détail complet de cette substitution et de ce
/// qu'il reste à construire côté serveur.
@MainActor
final class WalletRepository {
    static let shared = WalletRepository()
    private init() {}

    // MARK: - Historique (port de `getTransaction`/`WorkerTask`)

    // Corrigé (V3-F-093, SILENT-04) : décodage du tableau ENTIER en un seul `try?` — plusieurs
    // champs de `WalletTransaction` (`transactionId`/`currency`/`operatorName`/.../`type`) ne sont
    // PAS lenient (`decodeIfPresent(String.self,...)` strict sur le TYPE si la clé est présente),
    // donc UNE SEULE transaction avec un champ de type inattendu faisait échouer TOUT l'historique
    // d'un coup, vidé silencieusement en `[]`. Même motif déjà corrigé pour `TrophyRepository.
    // weeklyRank`/`SuggestionsRepository.decodeUsers`/`ChatRepository.decodeMessages` — `compactMap`
    // per-item avec diagnostic, pas un décodage global.
    func transactions(userId: String, limit: Int, offset: Int) async throws -> [WalletTransaction] {
        let value = try await APIClient.shared.get("transactions/\(userId)/\(limit)/\(offset)")
        guard let array = value["transactions"]?.toArray() else { return [] }
        let decoded = array.compactMap { item -> WalletTransaction? in
            guard let data = item.rawData else {
                print("WALLET TRANSACTIONS: item.rawData nil for one transaction — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(WalletTransaction.self, from: data)
            } catch {
                print("WALLET TRANSACTIONS: decode failure for one transaction — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("WALLET TRANSACTIONS: received=\(array.count), only \(decoded.count) usable — \(array.count - decoded.count) skipped, see above")
        }
        return decoded
    }

    // MARK: - Retrait (port de `submitWithdrawalRequest`/`submitWithdrawalByCrypto`)

    /// **Corrigé (V5-F-032, 2026-08-24)** — même cause que V5-F-031 : `TransportData.Post`
    /// (Android) n'appelle `onResonse`/`Result.SUCCESS` que si `error=="false"` ; tout rejet
    /// applicatif HTTP-200 (ex. `WITHDRAWAL_THRESHOLD_EXCEEDED`, testé explicitement par
    /// `WithdrawActivity.java:151-153`) déclenche `onError` → `Result.ERROR`, jamais affiché comme
    /// un succès. Cette fonction ignorait le champ `error`, faisant passer `WithdrawView.submit`
    /// dans sa branche succès (`didSubmit = true`) même sur rejet serveur.
    func submitWithdrawalRequest(
        userId: String, currentBalance: Double, requestedAmount: Double, calculatedMoney: Double, operatorName: String, country: String,
        phoneNumber: String, currency: String
    ) async throws {
        let params: [String: String] = [
            "userId": userId, "currentBalance": String(currentBalance), "requestedAmount": String(requestedAmount),
            "calculatedMoney": String(calculatedMoney), "operator": operatorName, "country": country, "phoneNumber": phoneNumber,
            "currency": currency,
        ]
        let value = try await APIClient.shared.post(params, endpoint: "withdrawalrequests")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "withdrawalrequests") }
    }

    /// Port de `submitWithdrawalByCrypto` — passe par `postToVPS` (serveur crypto DISTINCT du
    /// backend principal, `TransportData.postToVPS` cible une base URL différente).
    ///
    /// **Corrigé (V5-F-032, 2026-08-24)** — `TransportData.postToVPS` applique EXACTEMENT le même
    /// contrat `error`/`onError` que `Post` (vérifié : `Http/TransportData.java:683-712`), donc le
    /// même bug affectait ce chemin distinct — même correctif.
    func submitWithdrawalByCrypto(
        userId: String, currentBalance: Double, requestedAmount: Double, calculatedMoney: Double, operatorName: String, country: String,
        destAddress: String, currency: String
    ) async throws {
        let params: [String: String] = [
            "userId": userId, "currentBalance": String(currentBalance), "requestedAmount": String(requestedAmount),
            "calculatedMoney": String(calculatedMoney), "operator": operatorName, "country": country, "destAddress": destAddress,
            "currency": currency,
        ]
        let value = try await APIClient.shared.postToVPS(params, endpoint: "crypto/withdraw")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "crypto/withdraw") }
    }

    // MARK: - Conversion pièces → gemmes (port de `convert`)

    /// **Corrigé (V5-F-032, 2026-08-24)** — même cause que `submitWithdrawalRequest` ci-dessus :
    /// `WalletRepository.convert` (Android, `:166-195`) n'envoie `Result.SUCCESS` que sur
    /// `error=="false"` ; sans ce contrôle, `ConversionView.convert` affichait "Envoyé avec succès"
    /// même si aucune gemme n'avait été créditée côté serveur.
    func convert(userId: String, currentBalance: Double, requestedAmount: Double, gems: Double) async throws {
        let params: [String: String] = [
            "userId": userId, "currentBalance": String(currentBalance), "requestedAmount": String(requestedAmount),
            "requestedGems": String(gems),
        ]
        let value = try await APIClient.shared.post(params, endpoint: "convert")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "convert") }
    }

    // MARK: - Récompense pub rewarded (port de `updateToServer`)

    /// Port de `WalletRepository.updateToServer`/`EarnCoinsActivity.updateToServer`/
    /// `updateGemsToServer` (les 3 variantes Android envoient sur le MÊME endpoint `rewardedCoins`,
    /// seul `type` change : `"coins"` ou `"gems"`).
    ///
    /// **Corrigé (V5-F-031, 2026-08-24)** — `TransportData.Post` (Android) lit le champ
    /// applicatif `error` du corps JSON même sur une réponse HTTP 200 : si `error != "false"`,
    /// `callBack.onError(message)` est appelé au lieu de `onResonse`, et `updateToServer`'s
    /// `onError` ne remet JAMAIS `pendingCoinCount` à 0 — il l'incrémente au contraire du gain
    /// courant pour un nouveau essai (`WalletRepository.java:301-328`). Avant ce correctif,
    /// cette fonction ignorait le champ `error` (seul le status code HTTP était vérifié par
    /// `APIClient.post`), donc un rejet applicatif serveur (fraude anti-abus, limite quotidienne,
    /// session expirée) ne levait jamais d'exception ici : les 4 appelants (`EarnCoinsView`/
    /// `WithdrawView`/`TransferCoinsView`/`ConversionView`) exécutaient alors leur branche `do`
    /// (succès) à tort, remettant `pendingCoinsAmount`/`pendingGemsAmount` à 0 alors que le
    /// serveur n'avait jamais crédité le gain — perte silencieuse et définitive. `guard
    /// isBackendSuccess else { throw ... }` restaure exactement la sémantique retry qu'attendent
    /// déjà les 4 appelants via leur bloc `catch` (`pendingCoinsAmount += ...`, motif déjà
    /// utilisé ailleurs dans ce même fichier — `referralTotal`/`refreshBalance` juste en dessous).
    func creditReward(userId: String, totalAmount: Double, type: String) async throws {
        let params: [String: String] = ["id": userId, "coins": String(totalAmount), "type": type]
        let value = try await APIClient.shared.post(params, endpoint: "rewardedCoins")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "rewardedCoins") }
    }

    // MARK: - Parrainage (port de `getReferrelTotal`)

    func referralTotal(userId: String) async throws -> Int {
        let value = try await APIClient.shared.get("referral/total/\(userId)")
        guard value.isBackendSuccess else { return 0 }
        return (try? value.int("referralTotal")) ?? 0
    }

    // MARK: - Transfert P2P (port de `TransfertCoinsActivity` — pas de méthode dédiée côté
    // `WalletRepository.java` original, la logique vivait directement dans l'Activity)

    /// Port de `getUserByPhoneNumber`/endpoint `isPhoneOrEmailExiste` — recherche du destinataire.
    func findUser(phoneOrEmail: String) async throws -> User? {
        let value = try await APIClient.shared.post(["phoneOrEmail": phoneOrEmail], endpoint: "isPhoneOrEmailExiste")
        guard let data = value["user"]?.rawData else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    /// Port de `transfert.setOnClickListener` — émet `sender`/`receiver`/`column="coins"`/`quantity`.
    ///
    /// **Corrigé (V5-F-032, 2026-08-24)** — `TransfertCoinsActivity.java:128-150` : la déduction
    /// locale du solde (`coinCount - Integer.parseInt(m)`) n'a lieu QUE dans `onResonse` (succès) ;
    /// `onError` affiche un message d'erreur SANS toucher au solde. Sans ce contrôle,
    /// `TransferCoinsView.transfer` déduisait `UserSession.shared.coinsAmount` même sur rejet
    /// serveur — l'utilisateur voyait son solde baisser pour rien, alors qu'aucune pièce n'avait
    /// quitté le compte côté serveur.
    func transferCoins(senderId: String, receiverId: String, quantity: Int) async throws {
        let params: [String: String] = ["sender": senderId, "receiver": receiverId, "column": "coins", "quantity": String(quantity)]
        let value = try await APIClient.shared.post(params, endpoint: "transfert") // Faute d'orthographe RÉELLE côté serveur, préservée.
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "transfert") }
    }

    /// Port de `notifyUser` — déclenche une notification push générique côté serveur pour le
    /// destinataire d'un transfert.
    func notifyTransferReceived(userId: String) async throws {
        _ = try await APIClient.shared.post(["userId": userId], endpoint: "push")
    }

    // MARK: - Solde à jour (port de `WithdrawActivity.getRealAmount`)

    /// Port de `getRealAmount` — le champ `userData` est une chaîne JSON encodant UN SEUL objet
    /// (pas un tableau), enrobée artificiellement dans `"["+userData+"]"` côté Android pour
    /// pouvoir réutiliser le même désérialiseur de tableau `User[]` — reproduit à l'identique.
    func refreshBalance(userId: String) async throws -> Double {
        let value = try await APIClient.shared.get("getuserbyid/\(userId)")
        guard value.isBackendSuccess, let userDataString = try? value.string("userData"),
            let wrapped = "[\(userDataString)]".data(using: .utf8),
            let users = try? JSONDecoder().decode([User].self, from: wrapped)
        else { return UserSession.shared.coinsAmount }
        return users.first?.coinsAmount ?? UserSession.shared.coinsAmount
    }
}
