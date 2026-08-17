import SwiftUI

/// Port de la couche de rendu de `MessageListAdapter.java` (1353 lignes) + ses 9 `ViewHolder`
/// (`TextViewHolder`/`MessageAudioViewHolder`/`MessagePhotoViewHolder`/`MessageVideoViewHolder`/
/// `MessageStickerViewHolder`/`MessageGifViewHolder`/`MessageGiftViewHolder`/
/// `GraphicMessageViewHolder`/`MissedViewHolder`, tous lus en entier). Android distingue CHAQUE
/// type de message en 2 `viewType` RecyclerView (0/1, 2/3, …) uniquement pour satisfaire le pattern
/// ViewHolder/recyclage de vues — la seule vraie différence entre les deux est `isBelongsToCurrentUser`
/// (alignement, effets de bord upload vs download). SwiftUI n'a pas besoin de ce doublement : UNE
/// vue par type d'objet, alignement/effets calculés depuis `belongsToCurrentUser`.
///
/// **Constat vérifié en lisant `MessageAudioViewHolder.createWaveform()`** : la forme d'onde
/// affichée dans les bulles audio est un TABLEAU ALÉATOIRE (`new Random().nextInt(50)`), PAS une
/// extraction PCM réelle du fichier audio — reproduit fidèlement (pas "amélioré" en vraie analyse
/// audio), voir `randomWaveform()` ci-dessous.
enum MessageBubbleAlignment {
    static func forMessage(_ belongsToCurrentUser: Bool) -> HorizontalAlignment {
        belongsToCurrentUser ? .trailing : .leading
    }
}

// MARK: - Ligne de bulle (chrome commun : alignement, en-tête groupe, citation, bulle, pied)

/// Port du `bindView` commun à tous les `ViewHolder` (fond `bubble_incoming`/`bubble_outgoing`,
/// en-tête `nikname`/`username` pour un message de groupe reçu avec `verb=="post"`, boîte de
/// citation, corps spécifique au type, pied horodatage+statut) — port de
/// `TextViewHolder`/`MessageGiftViewHolder`/etc. `bindView`, consolidé en UNE vue paramétrée par
/// `object` plutôt que dupliqué par type (même règle déjà appliquée à `MessagePacket.buildPacketString`
/// au module 11 protocole).
struct ChatBubbleRow: View {
    let message: MessageLib
    let isGroup: Bool
    let onAppearEffects: () -> Void
    let onTapQuoteSwipe: () -> Void
    let onTapMedia: (ResultDataAction) -> Void
    let onLongPress: () -> Void

    private var isMine: Bool { message.belongsToCurrentUser }
    private var showGroupHeader: Bool { !isMine && isGroup && message.verb == "post" }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: MessageBubbleAlignment.forMessage(isMine), spacing: 4) {
                if showGroupHeader {
                    Text(message.nikname ?? message.username ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if message.isQuoted {
                    QuoteBoxView(title: message.quoteTitle, message: message.quoteMessage)
                }
                bodyView
                footer
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isMine ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            )
            if !isMine { Spacer(minLength: 48) }
        }
        .onAppear { onAppearEffects() }
        .onLongPressGesture { onLongPress() }
        .swipeActions(edge: isMine ? .leading : .trailing) {
            Button { onTapQuoteSwipe() } label: { Label("Répondre", systemImage: "arrowshape.turn.up.left") }
                .tint(.blue)
        }
    }

    @ViewBuilder private var bodyView: some View {
        switch message.object {
        case "text", "ai": TextBubbleBody(message: message)
        case "audio": AudioBubbleBody(message: message, isMine: isMine)
        case "photo", "sticker", "gif":
            MediaImageBubbleBody(message: message, isMine: isMine, onTap: { onTapMedia(.zoom(.photo)) })
        case "video": VideoBubbleBody(message: message, isMine: isMine, onTap: { onTapMedia(.zoom(.video)) })
        case "gift": GiftBubbleBody(message: message)
        case "graphic": GraphicPlaceholderBubbleBody(message: message)
        case "deletemessage":
            // R.string.messagedeleted / R.string.youdeletedthismessage
            Text(isMine ? "Vous avez supprimé ce message" : "Ce message a été supprimé")
                .italic().foregroundStyle(.secondary)
        default: TextBubbleBody(message: message)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(ChatDateFormatting.time(fromStampMillis: message.stamp))
                .font(.caption2).foregroundStyle(.secondary)
            if isMine { DeliveryStatusIcon(status: message.status) }
        }
    }
}

/// Port de `ResultData.PHOTO`/`VIDEO`/`AUDIO` × `ZOOM`/`DOWNLOAD`/`PLAY` — action déclenchée par un
/// tap sur le corps d'une bulle média, reprise en `enum` Swift plutôt que le couple `(String
/// object, int type)` original.
enum ResultDataAction {
    case zoom(MediaObjectKind)
    case download(MediaObjectKind)
    case play
}
enum MediaObjectKind { case photo, video, audio }

// MARK: - Statut de livraison (port de `getStatusDrawable`, `ic_acuser_inchat_0..3`)

/// Port de `ChatFragmentTest.getStatusDrawable`/`MessageListAdapter.getStatusDrawable` (les deux
/// existent côté Android — celui de l'adapter est CONFIRMÉ MORT, jamais appelé ; seul celui de
/// `ChatFragmentTest`, qui alimente `MessageLib.drawableId`, est réellement utilisé). 4 états
/// (0=envoi en cours, 1=envoyé, 2=distribué, 3+=lu), symboles SF Symbols en remplacement des PNG
/// `ic_acuser_inchat_*` (pas d'assets Android récupérables, adaptation de plateforme documentée).
struct DeliveryStatusIcon: View {
    let status: Int
    var body: some View {
        Group {
            switch status {
            case 0: Image(systemName: "clock")
            case 1: Image(systemName: "checkmark")
            case 2: Image(systemName: "checkmark.circle")
            default: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption2)
        .foregroundStyle(status < 3 ? .secondary : Color.accentColor)
    }
}

// MARK: - Corps texte (port de `TextViewHolder`/`salon_msg.xml`)

struct TextBubbleBody: View {
    let message: MessageLib
    var body: some View {
        Text(message.message ?? "")
            .font(.callout)
            .textSelection(.enabled)
    }
}

// MARK: - Boîte de citation (port de `quote_container`/`quote_title`/`quote_text`, `salon_msg.xml`)

struct QuoteBoxView: View {
    let title: String?
    let message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Color.red.opacity(0.6)).frame(height: 3)
            Text(title ?? "").font(.caption).foregroundStyle(.purple)
            Text(message ?? "").font(.caption).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }
}

// MARK: - Corps audio (port de `MessageAudioViewHolder`)

struct AudioBubbleBody: View {
    let message: MessageLib
    let isMine: Bool
    @State private var waves: [Int] = AudioBubbleBody.randomWaveform()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle.fill").font(.title2)
            WaveformSeekBar(
                waves: waves, progressPercent: 0, waveGap: 2,
                backgroundColor: isMine ? .white.opacity(0.5) : .gray.opacity(0.4),
                progressColor: .accentColor
            )
            .frame(height: 28)
            Text(Self.humanDuration(message.duration))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 160)
    }

    /// Port de `MessageAudioViewHolder.createWaveform()` — 50 barres ALÉATOIRES, PAS une vraie
    /// forme d'onde (confirmé en lisant le fichier Android, voir commentaire de tête de fichier).
    static func randomWaveform() -> [Int] { (0..<50).map { _ in Int.random(in: 5...55) } }

    /// Port de `getHumanTimeText` (`TimeUnit.MILLISECONDS.toMinutes/toSeconds`).
    static func humanDuration(_ raw: String?) -> String {
        guard let ms = raw.flatMap(Double.init) else { return "00:00" }
        let totalSeconds = Int(ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Corps image (photo/gif/sticker) — port de `MessagePhotoViewHolder`/`MessageGifViewHolder`/
// `MessageStickerViewHolder`, byte-pour-byte identiques côté Android sauf la source (`glid` vs
// `glidGif`) — consolidés ici en UNE vue.

struct MediaImageBubbleBody: View {
    let message: MessageLib
    let isMine: Bool
    let onTap: () -> Void

    private var sourcePath: String? {
        isMine ? message.localFileDirection : message.objectUrl
    }

    var body: some View {
        Group {
            if let sourcePath, let url = URL(string: sourcePath) {
                CDNAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                    default: mediaPlaceholder
                    }
                }
            } else {
                mediaPlaceholder
            }
        }
        .frame(maxWidth: 220, maxHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onTap() }
        .overlay(alignment: .center) {
            let uploaded = isMine ? message.isFileUploaded == 1 : true
            let downloaded = !isMine ? message.isFileDownloaded == 1 : true
            if !uploaded || !downloaded {
                ProgressView().tint(.white)
            }
        }
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
            .frame(width: 180, height: 140)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}

// MARK: - Corps vidéo (port de `MessageVideoViewHolder`)

struct VideoBubbleBody: View {
    let message: MessageLib
    let isMine: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if let path = isMine ? message.localFileDirection : (message.objectUrl ?? message.thumbnailUri),
                let url = URL(string: path) {
                CDNAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                    default: Color(.tertiarySystemBackground)
                    }
                }
            } else {
                Color(.tertiarySystemBackground)
            }
            let ready = isMine ? message.isFileUploaded == 1 : message.isFileDownloaded == 1
            if ready {
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: 220, maxHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onTap() }
    }
}

// MARK: - Corps cadeau (port de `MessageGiftViewHolder`/`GiftBadgeView`/`GiftCatalogHelper`)

struct GiftBubbleBody: View {
    let message: MessageLib
    var body: some View {
        let gift = GiftCatalog.resolve(message.giftId)
        HStack(spacing: 6) {
            Text(gift?.emoji ?? GiftCatalog.emoji(for: message.giftId)).font(.title2)
            Text(gift.map { "\($0.name) · \($0.price)" } ?? "Cadeau") // R.string.gift
                .font(.caption)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
    }
}

// MARK: - Message Graphic (module 14 — port de `GraphicMessageViewHolder`)

/// Port de `GraphicMessageViewHolder`/`PBSView.displayWhenItReady` en lecture seule — décode le lot
/// compact (`message.message`, déjà substitué depuis `MgGraphic` par `ChatViewModel.onIncoming`/
/// `MessageRepository`, voir module 11) via `PBSCanvasEngine.loadRecordedBatch`, puis rejoue les
/// traits dans le MÊME moteur de rendu que le Shareboard (`PBSCanvasView`), `isInteractive: false`.
struct GraphicPlaceholderBubbleBody: View {
    let message: MessageLib
    @StateObject private var engine = PBSCanvasEngine()

    var body: some View {
        PBSCanvasView(engine: engine, isInteractive: false)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear { engine.localViewSize = CGSize(width: 220, height: 220); engine.loadRecordedBatch(message.message) }
    }
}

// MARK: - Appel manqué (port de `MissedViewHolder`)

struct MissedCallBubbleRow: View {
    let message: MessageLib
    let text: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Spacer()
                Label(text, systemImage: "phone.arrow.down.left.fill")
                    .font(.caption).foregroundStyle(.red)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - Messages système (information/shareboard/date/header) — port de
// `InformationViewHolder`/`ShareBordInformationViewHolder`/`DateHolder`/`Header`, tous des bandeaux
// centrés pleine largeur, pas des bulles alignées.

struct SystemInfoRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
    }
}

struct DateSeparatorRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color(.tertiarySystemBackground)))
            .frame(maxWidth: .infinity)
    }
}

/// Port de `Header` (`header_layout.xml`) — bandeau description de groupe, affiché seulement si
/// `RosterModel.description` est non vide (reproduit la condition `!description.isEmpty()` de
/// `Header.bindView`).
struct GroupHeaderRow: View {
    let description: String
    var body: some View {
        Text(description)
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(8)
            .background(Color(.tertiarySystemBackground))
    }
}

/// Port de `Subscribe`/`RenewSubscription` (`subscribe_layout.xml`/`renewsubscription_layout.xml`)
/// — bandeau de paiement groupe. **PAS fonctionnel** : la vraie action (`group/subscribe`,
/// `group/renewsubscription`, débit `COINS_AMOUNT`) dépend du module 15 (Wallet/Paiements), pas
/// encore porté — bouton présent, action réseau différée et documentée plutôt que devinée.
struct SubscriptionBannerRow: View {
    let title: String
    let isRenewal: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.footnote)
            // R.string.renew_subscription / R.string.subscribe
            Button(isRenewal ? "Renouveler l'abonnement" : "S'abonner", action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.tertiarySystemBackground))
    }
}
