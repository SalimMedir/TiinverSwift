import PhotosUI
import SwiftUI

/// Port de `messagerie/ui/FragmentPbs.java` (mise en page `fragment_pbs.xml`/`PBSCompound`, non
/// lues en détail — reconstruites depuis les `findViewById` observés dans `PBSCompound.init()`) —
/// écran du Shareboard temps réel : barre d'outils (pinceau/texte/emoji/image/fond/palette),
/// indicateur d'état de connexion, bouton "démarrer" pour le créateur du salon.
///
/// **Non porté cette session, documenté** : carrousel de bannières publicitaires
/// (`BannerAdapter`), tutoriel `TapTargetView` — décoratifs, voir avertissement `PBSCanvasView.swift`.
struct ShareboardView: View {
    @StateObject private var viewModel: PBSViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTool: Tool?
    @State private var pendingTextInput = ""
    @State private var isMicMuted = true
    @State private var mediaPickerItem: PhotosPickerItem?
    @State private var wallpaperPickerItem: PhotosPickerItem?

    private enum Tool: Equatable { case paint, text, palette }

    init(profile: ChatProfile, receiver: String, chatType: String, status: Int) {
        _viewModel = StateObject(wrappedValue: PBSViewModel(profile: profile, receiver: receiver, chatType: chatType, status: status))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PBSCanvasView(engine: viewModel.engine)
                if viewModel.showStartButton {
                    startOverlay
                }
            }
            .navigationTitle(connectionLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { viewModel.leave(); dismiss() } // R.id.close_animemes / X
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(viewModel.connectedUserCount)") // port de `drawTiinverIcon` (compteur d'utilisateurs)
                        .font(.caption).padding(6).background(.thinMaterial, in: Circle())
                }
            }
            .safeAreaInset(edge: .bottom) { toolbar }
        }
    }

    private var connectionLabel: String {
        switch viewModel.connectionState {
        case .idle: return ""
        case .waiting: return "En attente…" // R.string.waiting
        case .connecting: return "Connexion…" // R.string.connecting
        case .connected: return "Connecté" // R.string.connected
        case .closed: return "Fermé" // R.string.close
        }
    }

    /// Port de `startContainer`/`startbtn` — visible uniquement pour le créateur du salon
    /// (`STATUS==1`).
    private var startOverlay: some View {
        VStack(spacing: 12) {
            Text(connectionLabel).foregroundStyle(.secondary)
            Button("Démarrer le Shareboard") { viewModel.startTapped() } // R.string.start (supposé)
                .buttonStyle(.borderedProminent)
        }
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Barre d'outils (port de `PBSCompound.init`/`onClick` — pinceau/texte/emoji/image/
    // fond/palette/annuler/micro)

    private var toolbar: some View {
        HStack(spacing: 20) {
            Button {
                isMicMuted.toggle()
                viewModel.setMicrophoneMuted(isMicMuted)
            } label: { Image(systemName: isMicMuted ? "mic.slash.fill" : "mic.fill") } // R.id.callBtn

            Button { toggleTool(.paint) } label: { Image(systemName: "pencil.tip") } // R.id.ic_paint
                .foregroundStyle(selectedTool == .paint ? Color.accentColor : .primary)

            Button { toggleTool(.palette) } label: { Image(systemName: "paintpalette") } // R.id.ic_palete
                .foregroundStyle(selectedTool == .palette ? Color.accentColor : .primary)

            Button { toggleTool(.text) } label: { Image(systemName: "textformat") } // R.id.ic_text
                .foregroundStyle(selectedTool == .text ? Color.accentColor : .primary)

            PhotosPicker(selection: $mediaPickerItem, matching: .images) {
                Image(systemName: "photo.badge.plus") // R.id.ic_add
            }
            PhotosPicker(selection: $wallpaperPickerItem, matching: .images) {
                Image(systemName: "photo") // R.id.ic_wallpaper
            }

            Button { viewModel.engine.undoLastStroke() } label: { Image(systemName: "arrow.uturn.backward") } // R.id.undo

            Spacer()

            Button { viewModel.engine.previousPage(isFromMe: true) } label: { Image(systemName: "chevron.left") } // R.id.back
            Button { viewModel.engine.nextPage(isFromMe: true) } label: { Image(systemName: "chevron.right") } // R.id.next
        }
        .font(.title3)
        .padding(12)
        .background(.bar)
        .onChange(of: mediaPickerItem) { item in Task { await placePickedImage(item, asWallpaper: false) } }
        .onChange(of: wallpaperPickerItem) { item in Task { await placePickedImage(item, asWallpaper: true) } }
        .alert("Texte", isPresented: Binding(get: { selectedTool == .text }, set: { if !$0 { selectedTool = nil } })) {
            TextField("Message", text: $pendingTextInput)
            Button("Ajouter") { addTextObject(); selectedTool = nil }
            Button("Annuler", role: .cancel) { selectedTool = nil }
        }
        .sheet(isPresented: Binding(get: { selectedTool == .palette }, set: { if !$0 { selectedTool = nil } })) {
            paletteSheet
        }
    }

    private func toggleTool(_ tool: Tool) {
        if tool == .palette {
            selectedTool = .palette
            return
        }
        viewModel.engine.action = (viewModel.engine.action == tool.androidAction) ? nil : tool.androidAction
        selectedTool = viewModel.engine.action == nil ? nil : tool
    }

    /// Port de `PaintListAdapter`/`onColorChoosed` — palette réduite (Android charge une liste de
    /// couleurs XML non lue cette passe), suffisante pour choisir la couleur du pinceau.
    private var paletteSheet: some View {
        let colors: [Int] = [0xFF00_0000, 0xFFFF_FFFF, 0xFFFF_0000, 0xFF00_9900, 0xFF00_66FF, 0xFFFF_CC00, 0xFFFF_6600, 0xFF99_00CC]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
            ForEach(colors, id: \.self) { value in
                Button {
                    viewModel.engine.paintColor = value
                    selectedTool = nil
                } label: {
                    Circle().fill(PBSCanvasView.color(fromARGB: value)).frame(width: 36, height: 36)
                }
            }
        }
        .padding()
        .presentationDetents([.height(160)])
    }

    /// Port de `PBSCompound.onClick(ic_text)`/`onClick(containerEditText)` — place la bulle au
    /// centre de la vue (Android positionne à `et.getX()/getY()` du champ de saisie flottant, non
    /// modélisé ici ; centre choisi comme position par défaut raisonnable).
    private func addTextObject() {
        guard !pendingTextInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var data = PBSEditorData()
        data.type = "text"
        data.action = "text"
        data.text = pendingTextInput
        data.textColor = 0xFFFF_FFFF
        data.containerColor = 0x8000_0000
        data.textWidth = viewModel.engine.localViewSize.width / 2
        data.textHeight = viewModel.engine.localViewSize.height / 2
        data.username = viewModel.engine.username
        viewModel.engine.placeObject(data)
        pendingTextInput = ""
    }

    /// Port de `PBSCompound.add`/`addPictureBackground` — `asWallpaper` sépare le fond (local,
    /// non synchronisé, voir `PBSCanvasEngine.backgroundImageData`) d'un objet "media1" placé
    /// (synchronisé à tous les pairs).
    private func placePickedImage(_ item: PhotosPickerItem?, asWallpaper: Bool) async {
        guard let item, let imageData = try? await item.loadTransferable(type: Data.self) else { return }
        if asWallpaper {
            viewModel.engine.backgroundImageData = imageData
            wallpaperPickerItem = nil
            return
        }
        var data = PBSEditorData()
        data.type = "media1"
        data.action = "media"
        data.bitmapData = imageData
        data.bitmapWidth = 160
        data.bitmapHeight = 160
        data.posX = viewModel.engine.localViewSize.width / 4
        data.posY = viewModel.engine.localViewSize.height / 4
        data.username = viewModel.engine.username
        viewModel.engine.placeObject(data)
        mediaPickerItem = nil
    }
}

private extension ShareboardView.Tool {
    var androidAction: String {
        switch self {
        case .paint: return "drawPath"
        case .text: return "text"
        case .palette: return ""
        }
    }
}
