import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Port de `BaseCameraFragment.pickImageOrVideo`/`pickMedia` — lu en entier avant d'écrire ce
/// fichier : `ActivityResultContracts.PickVisualMedia` avec le filtre `ImageAndVideo`
/// (`PickVisualMediaRequest.Builder().setMediaType(PickVisualMedia.ImageAndVideo.INSTANCE)`),
/// sélection UNIQUE (aucun appel à un `setMaxItems`, donc 1 par défaut côté Android aussi — pas
/// une limitation ajoutée côté iOS). Après sélection, Android détermine image vs vidéo via le
/// MIME type (`ContentResolver.getType`) puis route séparément.
///
/// `PHPickerViewController` (UIKit, via `UIViewControllerRepresentable`) choisi plutôt que
/// `PhotosPicker` SwiftUI natif — vérifié disponible dès iOS 16.0 (introduit à WWDC22 avec
/// `PhotosUI`, donc compatible avec la cible du projet), mais écarté ici : la sélection
/// image+vidéo mélangée avec accès direct à un fichier local (équivalent de `Utils.getPath`, qui
/// résout un vrai chemin de fichier, pas juste des octets) est plus directe via
/// `NSItemProvider.loadFileRepresentation` que via `Transferable`, qui exigerait un type `Movie`
/// custom pour les vidéos sans bénéfice supplémentaire ici.
struct GalleryPickerView: UIViewControllerRepresentable {
    var onImagePicked: (URL) -> Void
    var onVideoPicked: (URL) -> Void
    var onCancel: () -> Void
    /// **Ajouté (2026-08-28, V6-F-003)** — filtre optionnel, `.videos` réutilisé par le sélecteur
    /// dédié "Extraire" d'Animems (système de sélection vidéo-seule, comme Android). Défaut
    /// inchangé pour tous les appelants existants (images+vidéos).
    var filter: PHPickerFilter = .any(of: [.images, .videos])

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = filter
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GalleryPickerView

        init(_ parent: GalleryPickerView) {
            self.parent = parent
        }

        /// Port du callback de `registerForActivityResult(PickVisualMedia())` — `uri == null`
        /// (annulation Android) correspond ici à `results.isEmpty`.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onCancel()
                return
            }
            let provider = result.itemProvider

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    // `loadFileRepresentation` supprime le fichier temporaire dès que ce handler
                    // retourne — copie SYNCHRONE obligatoire avant de repasser sur le main thread
                    // (piège connu de cette API, pas un oubli).
                    //
                    // Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-058, Phase B P2) —
                    // `guard let url else { return }` laissait la feuille de sélection bloquée sans
                    // AUCUN callback en cas d'échec de chargement (asset iCloud non téléchargé,
                    // permission révoquée en cours de sélection, erreur I/O transitoire) — ni
                    // `onVideoPicked`, ni `onCancel`. Aligné sur le repli déjà en place pour un
                    // échec de COPIE locale (`localCopy == nil` → `onCancel()`, quelques lignes plus
                    // bas) et sur la garde `results.first == nil` ci-dessus.
                    guard let url else {
                        DispatchQueue.main.async { self.parent.onCancel() }
                        return
                    }
                    let localCopy = Self.copyToTemporaryFile(url)
                    DispatchQueue.main.async {
                        if let localCopy { self.parent.onVideoPicked(localCopy) } else { self.parent.onCancel() }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    // V4-F-058 — même correctif que la branche vidéo ci-dessus.
                    guard let url else {
                        DispatchQueue.main.async { self.parent.onCancel() }
                        return
                    }
                    let localCopy = Self.copyToTemporaryFile(url)
                    DispatchQueue.main.async {
                        if let localCopy { self.parent.onImagePicked(localCopy) } else { self.parent.onCancel() }
                    }
                }
            } else {
                parent.onCancel()
            }
        }

        private static func copyToTemporaryFile(_ sourceURL: URL) -> URL? {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                return destination
            } catch {
                return nil
            }
        }
    }
}
