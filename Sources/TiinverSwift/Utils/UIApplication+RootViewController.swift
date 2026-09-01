import UIKit

extension UIApplication {
    /// Nécessaire pour présenter l'UI `GIDSignIn` (Google Sign-In), qui demande un
    /// `UIViewController` de présentation — sans équivalent direct côté Android (Credential
    /// Manager s'attache à l'`Activity` implicitement).
    var rootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    /// Ajouté pour "Sign in with Apple" (`AppleSignInCoordinator.swift`) — `ASAuthorizationController.
    /// presentationContextProvider` demande un `ASPresentationAnchor` (= `UIWindow` sur iOS), pas un
    /// `UIViewController` comme `rootViewController` ci-dessus.
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
