import CropViewController
import SwiftUI
import UIKit

/// Port de `android/views/CroperView.java` — remplace le recadreur Android vendorisé
/// (`CropImageView`/`CropOverlayView`/`CropWindowHandler`/`CropWindowMoveHandler`, ~5000 lignes de
/// géométrie de poignées tactiles à main levée) par `TOCropViewController` (SPM, vérifié : dernier
/// push récent, non archivé, `platforms: [.iOS(.v12)]` confirmé dans son `Package.swift` réel au
/// tag `3.2.0` — voir `project.yml`/journal module 9). Wrapper `UIViewControllerRepresentable`
/// autour de la seule API réellement nécessaire (`CropViewController(croppingStyle:image:)`,
/// `onDidCropToRect`/`onDidFinishCancelled`), vérifiée directement dans le fichier source Swift
/// réel de la librairie avant écriture (pas devinée). **Depuis le 2026-08-20 (V3-F-125, Phase B
/// P1)**, `onDidCropToCircleImage` n'est plus utilisé : le style `.circular` (carré 1:1 verrouillé)
/// a été abandonné au profit de `.default` + masque ovale appliqué après coup, voir
/// `makeUIViewController` ci-dessous.
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
        // **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-125, Phase B P1)** — `.circular`
        // verrouille la zone de recadrage à un carré 1:1 (toujours un cercle parfait). Android ne
        // fait JAMAIS ça pour le mode "Ovale" : `CropFragment.java` n'appelle jamais
        // `setFixedAspectRatio(true)` (grep exhaustif) et `CropImageViewOptions.fixAspectRatio`
        // vaut `false` par défaut — la zone de recadrage ovale Android est une ELLIPSE LIBRE,
        // ratio quelconque. `.default` (zone de recadrage rectangulaire libre, DÉJÀ le style du
        // mode "Rectangle") reproduit ce ratio libre ; le masque elliptique est appliqué APRÈS
        // coup sur le rectangle recadré via `PhotoCropUtils.toOvalImage` (port direct de
        // `CropImage.toOvalBitmap`, écrit lors d'un correctif antérieur mais jamais câblé —
        // confirmé par grep : zéro appelant avant ce correctif).
        let croppingStyle: CropViewCroppingStyle = .default
        let controller = CropViewController(croppingStyle: croppingStyle, image: image)
        controller.onDidCropToRect = { croppedImage, _, _ in
            if shape == .oval, let cgImage = croppedImage.cgImage, let oval = PhotoCropUtils.toOvalImage(cgImage) {
                // `toOvalImage` opère sur les pixels bruts du `CGImage` sans tenir compte d'une
                // éventuelle métadonnée d'orientation — on reprend donc telle quelle
                // `croppedImage.imageOrientation` (au lieu de supposer `.up`) pour que le résultat
                // masqué reste visuellement identique au rectangle recadré d'origine.
                onCropped(UIImage(cgImage: oval, scale: croppedImage.scale, orientation: croppedImage.imageOrientation))
            } else {
                onCropped(croppedImage)
            }
        }
        controller.onDidFinishCancelled = { _ in
            onCancelled()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {}
}
