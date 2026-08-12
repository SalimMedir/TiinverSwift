import CropViewController
import SwiftUI
import UIKit

/// Port de `android/views/CroperView.java` — remplace le recadreur Android vendorisé
/// (`CropImageView`/`CropOverlayView`/`CropWindowHandler`/`CropWindowMoveHandler`, ~5000 lignes de
/// géométrie de poignées tactiles à main levée) par `TOCropViewController` (SPM, vérifié : dernier
/// push récent, non archivé, `platforms: [.iOS(.v12)]` confirmé dans son `Package.swift` réel au
/// tag `3.2.0` — voir `project.yml`/journal module 9). Wrapper `UIViewControllerRepresentable`
/// autour de la seule API réellement nécessaire (`CropViewController(croppingStyle:image:)`,
/// `onDidCropToRect`/`onDidCropToCircleImage`/`onDidFinishCancelled`), vérifiée directement dans
/// le fichier source Swift réel de la librairie avant écriture (pas devinée).
///
/// **Ce qui N'EST PAS repris de `CroperView.java`** : `FreeformCropView` (mode non couvert par
/// TOCropViewController, porté séparément — voir `FreeformCropView.swift`) ; `removeBackground`
/// (méthode statique de tolérance de couleur unique, confirmée MORTE par grep — zéro appelant dans
/// tout le dépôt, différente de `RemoveBackground.removeBackgroundAdvanced` qui EST utilisée) ;
/// les animations de pression de bouton (`animateButtonPress`)/overlay de progression
/// (`showProgressOverlay`) — pure présentation SwiftUI standard, aucune logique à porter.
struct PhotoCropView: UIViewControllerRepresentable {
    enum Shape {
        case rectangle
        case oval
    }

    let image: UIImage
    var shape: Shape = .rectangle
    /// Port de `handleFlip` — `CropImageView.setFlippedHorizontally`, sans équivalent direct
    /// exposé par `CropViewController` (l'image doit être pré-retournée avant présentation,
    /// TOCropViewController n'expose pas de flip horizontal en cours d'édition — voir note
    /// "Points à vérifier" module 9).
    var onCropped: (UIImage) -> Void
    var onCancelled: () -> Void

    func makeUIViewController(context: Context) -> CropViewController {
        let croppingStyle: CropViewCroppingStyle = shape == .oval ? .circular : .default
        let controller = CropViewController(croppingStyle: croppingStyle, image: image)
        controller.onDidCropToRect = { croppedImage, _, _ in
            onCropped(croppedImage)
        }
        controller.onDidCropToCircleImage = { croppedImage, _, _ in
            onCropped(croppedImage)
        }
        controller.onDidFinishCancelled = { _ in
            onCancelled()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {}
}
