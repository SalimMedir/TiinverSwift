import Foundation

/// Port PARTIEL de `android/memes/FrameAdapter.java`.
///
/// **Découverte importante (module 8, dernière passe)** : `FrameAdapter` ne fait PAS partie du
/// système `AnimationEngine`/keyframes déjà porté (`AnimationEngine.swift`, `LayerRenderer.swift`,
/// etc.) — c'est le pilote d'une bande de vignettes (`RecyclerView` horizontal, `frameList` dans
/// `AnimemesCompound.java`) pour un sous-système SÉPARÉ de capture "image par image" façon
/// flipbook, piloté par `mView.newFrame()`/`deleteFrame()`/`setOnFrameConnectionListener` côté
/// `MemesView2` — AUCUNE de ces méthodes `MemesView2` n'a été lue dans ce module. `FrameAdapter`
/// dépend aussi de classes entièrement non lues : `FrameData`, `Frame` (modèle sérialisé JSON via
/// Gson, distinct de `SerializableAnimationObject`), `SerializableManager` (persistance disque),
/// `ImageViewRound`/`ButtonAddFrame` (vues custom supplémentaires, NON comptées dans la liste des
/// ~10-14 vues de ce module), et une ancienne classe `MemesView` (sans le `2`) référencée par un
/// `ViewHolder` de type `3` — dont le code semble mort/expérimental (`TestViewHolder`, jamais
/// atteint dans `getItemViewType` en pratique d'après le `FrameData.getType()` réel observable
/// ailleurs).
///
/// **Décision** : documenter cette découverte comme un sous-système SUPPLÉMENTAIRE non exploré
/// (à la manière de Motion Templates/AI Generation/RemoveBackground du point 2 du plan module 8),
/// PAS comme faisant partie de "TimelineView et consorts" au sens de la timeline de calques
/// (`TimelineItem`/`PlaylistEntry`, déjà portés). Seule la logique de gestion de LISTE de
/// `FrameAdapter` (indépendante de `FrameData`/`Frame`/Android View) est portée ci-dessous — elle
/// est directement réutilisable quel que soit le type d'élément final une fois ce sous-système
/// exploré.
struct FrameListState<Frame> {
    private(set) var items: [Frame] = []

    /// Port de `add` — insère en position 1 (juste après l'élément 0, généralement le bouton
    /// "+") sauf si la liste ne contient qu'un seul élément, auquel cas on ajoute à la fin.
    mutating func add(_ item: Frame) {
        if items.count == 1 {
            items.append(item)
        } else {
            items.insert(item, at: min(1, items.count))
        }
    }

    /// Port de `addWidthLimit` — comme `add`, avec éviction FIFO au-delà de 50 éléments (retire
    /// l'élément d'index 1, PAS le plus ancien au sens strict puisque les insertions se font aussi
    /// en position 1 — reproduit tel quel, y compris cette particularité de l'original).
    mutating func addWithLimit(_ item: Frame, maxCount: Int = 50) {
        if items.count == 1 {
            items.append(item)
        } else {
            if items.count >= maxCount, items.count > 1 {
                items.remove(at: 1)
            }
            items.insert(item, at: min(1, items.count))
        }
    }

    /// Port de `addHead` — ajoute à la fin (nom trompeur dans l'original : ajoute en QUEUE de
    /// liste, pas en tête — reproduit tel quel malgré l'incohérence de nommage Android).
    mutating func addAtEnd(_ item: Frame) {
        items.append(item)
    }

    mutating func insert(_ item: Frame, at index: Int) {
        items.insert(item, at: index)
    }

    mutating func update(_ item: Frame, at index: Int) {
        guard index >= 0, index < items.count else { return }
        items[index] = item
    }

    /// Port de `removeView` — retrait par position (la persistance disque associée,
    /// `SerializableManager.removeSerializable`, reste hors scope — voir note de tête de fichier).
    @discardableResult
    mutating func remove(at index: Int) -> Frame? {
        guard !items.isEmpty, index >= 0, index < items.count else { return nil }
        return items.remove(at: index)
    }
}
