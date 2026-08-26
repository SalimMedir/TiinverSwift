import Foundation

/// Port de `engine/template/MotionTemplate.java`/`MotionTrack.java` (modèles de données, lus via
/// `MotionTemplateManager.java` — les deux fichiers modèles eux-mêmes n'ont pas été relus en entier,
/// leurs champs déduits fidèlement des getters/setters utilisés dans `extract`/`apply`, tous
/// vérifiés). `Codable` remplace `Serializable`+`SerializableManager` (Android sérialise l'objet
/// Java brut sur disque ; ici, JSON via `Codable`, même rôle — un fichier par modèle, pas de
/// base de données).
struct MotionTemplate: Codable, Identifiable {
    var id: String
    var createdAt: Int64
    var canvasWidth: Int
    var canvasHeight: Int
    var hasAudio: Bool
    var audioLocalPath: String?
    var audioFileName: String?
    var totalFrames: Int
    var tracks: [MotionTrack]
    /// Port de `MotionTemplate.java:10` (`isFromCommunity`, "vient du serveur ?") — mis à `true`
    /// UNIQUEMENT par `CommunityTemplateRepository` (comme `CommunityTemplateGalleryView.java:
    /// 619-620` le fait côté Android), jamais persisté dans le fichier `.tmpl` lui-même (fidèle à
    /// l'original Java, un champ runtime jamais sérialisé avec l'objet — voir `CodingKeys`
    /// ci-dessous, **V5-F-083**). Exclu de `CodingKeys` : un fichier `.tmpl` déjà sauvegardé
    /// localement (avant ce correctif) ou un JSON de template communautaire téléchargé n'a jamais
    /// cette clé — l'omettre du décodage synthétisé (au lieu d'un `Bool` non-optionnel requis)
    /// évite un échec de décodage sur CHAQUE modèle déjà persisté sur l'appareil.
    var isFromCommunity: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, canvasWidth, canvasHeight, hasAudio, audioLocalPath, audioFileName, totalFrames, tracks
    }

    /// Port de `resolveAudio`/`AudioResult` — simplifié en 3 cas directement testables, pas un enum
    /// séparé côté Swift (appelé une seule fois, à l'endroit d'usage).
    var audioLocalAvailable: Bool {
        guard let path = audioLocalPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Port de `MotionTrack` — une piste par calque source. Champs shape/masque TOUS présents même
/// pour un calque bitmap/texte ordinaire (valeurs par défaut ignorées à l'application, comme
/// l'original Java où ce sont de simples champs de classe, pas une hiérarchie de sous-types).
struct MotionTrack: Codable {
    var label: String?
    var offsetX: Int = 0
    var offsetY: Int = 0
    var objectWidth: Double = 0
    var objectHeight: Double = 0
    var startFrame: Int = 0
    var endFrame: Int = 0
    var locked: Bool = false
    var holdLast: Bool = false
    var objectType: String?

    /// Matrices 9 éléments (`Transform.matrixValues`), translation normalisée par la largeur/hauteur
    /// du canevas SOURCE au moment de l'extraction — dénormalisée par le canevas CIBLE à
    /// l'application (voir `MotionTemplateManager.apply`), permettant de rejouer un modèle sur un
    /// canevas de taille différente.
    var matrices: [[Float]] = []

    /// Port de `maskAutoFrames` — `nil`/vide si le calque n'a pas de `maskTransforms` capturées en
    /// mode automatique. `[offsetX, offsetY, scale, rotation]` normalisés par calque, 4 éléments.
    var maskAutoFrames: [[Float]]?

    struct KeyframeData: Codable {
        var propertyName: String
        var timestampNs: Int64
        var values: [Float]
    }
    var keyframes: [KeyframeData] = []

    // Formes (SHAPE_RECT/SHAPE_CIRCLE/SHAPE_LINE).
    var shapeColor: UInt32 = 0xFFFF_FFFF
    var shapeOpacity: Float = 1
    var shapeCornerRadius: Float = 0
    var shapeLineThickness: Float = 8
    var shapeStrokeWidth: Float = 0
    var shapeW: Int = 0
    var shapeH: Int = 0

    // Masques (`MASK_RENDER` — port moderne `appliedMaskType`, voir note de tête de fichier
    // `MotionTemplateManager.swift` sur `MASK`/legacy PAS reproduit).
    var maskTypeName: String?
    var maskInverted: Bool = false
    var maskColor: UInt32 = 0xFFFF_FFFF
    var maskOpacity: Float = 1
    var maskFeather: Float = 0
    var maskOffsetX: Float = 0
    var maskOffsetY: Float = 0
    var maskScale: Float = 1
    var maskMirrorGap: Float = 0.06
    var maskRotation: Float = 0

    var isShape: Bool {
        objectType == "SHAPE_RECT" || objectType == "SHAPE_CIRCLE" || objectType == "SHAPE_LINE"
    }
    var isMaskRender: Bool { objectType == "MASK_RENDER" }
}
