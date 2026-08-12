import SwiftUI

/// Port de `messagerie/ui/FragmentMessageGraphic.java` (295 lignes, lu en entier) — capture LOCALE
/// (aucun réseau, contrairement au Shareboard, module 13) d'un dessin libre, envoyé en UN SEUL
/// message "graphic" une fois terminé (`btnSendTextMsg`). Réutilise le MÊME moteur
/// `PBSCanvasEngine`/`PBSCanvasView` que le Shareboard — confirmé en lisant les deux Fragment
/// Android, qui instancient tous deux LITTÉRALEMENT `PBSCompound`/`PBSView`.
///
/// **Limitation Android reproduite fidèlement, PAS corrigée** : `FragmentMessageGraphic.
/// onSendPBStreamData(EditorData, String)` (objets placés — image/texte/sticker) construit un
/// `JSONObject` local puis... ne fait RIEN d'autre avec (jamais ajouté à `datas`, jamais envoyé) —
/// SEUL `onSendPBSTouchSreamListner(MotionEventData)` alimente réellement `datas`
/// (`GraphicMessageCodec.encodeTouchEventCompact`), qui est ce qui part dans le message final
/// (`encodeTouchBatch`). Un objet image/texte/sticker ajouté pendant la composition d'un Message
/// Graphic est donc VISUELLEMENT présent à l'écran mais DISPARAÎT du message envoyé — vérifié en
/// comparant `FragmentMessageGraphic` à `FragmentPbs` (celui-ci, lui, envoie bien `onSendPBStreamData`
/// via le socket). Seul le dessin libre (`drawPath`) survit à l'envoi côté Android ; reproduit ici à
/// l'identique plutôt que "corrigé" silencieusement — le portage documente les bugs trouvés, il ne
/// les corrige pas sans le signaler.
struct MessageGraphicComposeView: View {
    @StateObject private var engine = PBSCanvasEngine()
    @Environment(\.dismiss) private var dismiss
    let onSend: (String) -> Void

    @State private var recordedBatch: [CompactTouchEvent] = []

    init(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
    }

    var body: some View {
        NavigationStack {
            PBSCanvasView(engine: engine)
                .navigationTitle("Message graphique") // R.string.graphic
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Annuler") { dismiss() } // R.id.closeFrame
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            let compressed = GraphicMessageCodec.encodeTouchBatch(recordedBatch)
                            onSend(compressed)
                            dismiss()
                        } label: { Image(systemName: "paperplane.fill") } // R.id.btnSendTextMsg
                        .disabled(recordedBatch.isEmpty)
                    }
                }
        }
        .onAppear {
            // Port de `pbs_compound.setDataCompress(2)` — cadence de capture DIFFÉRENTE du
            // Shareboard temps réel (3), vérifiée dans `FragmentMessageGraphic.onCreateView`.
            engine.dataCompressRate = 2
            engine.action = "drawPath"
            // Port de `PBStreamActionListener.onSendPBSTouchSreamListner` — accumulation locale
            // pure (PAS de réseau), contrairement à `PBSViewModel.sendTouch` (module 13).
            engine.onLocalTouch = { event in recordedBatch.append(GraphicMessageCodec.encodeTouchEventCompact(event)) }
        }
    }
}
