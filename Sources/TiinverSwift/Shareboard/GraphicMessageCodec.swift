import CoreGraphics
import Foundation

/// Port de `com.animems.engine.android.codec.graphic.GraphicMessageCodec` (266 lignes, lu en
/// entier) + `CompactTouchEvent.java`/`CompactEditorData.java` (formats fil) — codec de
/// compression utilisé À LA FOIS par le Shareboard temps réel (module 13, un `PBSTouchEvent`/
/// `PBSEditorData` par appel `encode*`) et par Message Graphic (module 14, un LOT de
/// `CompactTouchEvent` via `encodeTouchBatch`/`decodeGraphicMessage`).
///
/// **Noms de clés JSON reproduits À L'IDENTIQUE, PAS renommés** (`id`,`a`,`n`,`x0`,`y0`,`x1`,`y1`,
/// `s`,`c`,`t`,`sw`,`sh` / `id`,`tp`,`ac`,`tc`,`cc`,`tx`,`tw`,`th`,`l`,`t`,`px`,`py`,`bw`,`bh`,`bb`)
/// — un pair Android encore en circulation doit pouvoir désérialiser ce que ce client émet, et
/// réciproquement (le canal de données WebRTC/l'événement socket ne transitent PAS par un serveur
/// qui reformaterait les données, c'est un payload JSON opaque de bout en bout).
enum GraphicMessageCodec {
    // MARK: - TOUCH EVENT (dessin temps réel)

    static func encodeTouchEvent(_ src: PBSTouchEvent) -> String {
        let compact = compact(from: src)
        return (try? Self.encoder.encode(compact)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decodeTouchEvent(_ json: String) -> PBSTouchEvent? {
        guard let data = json.data(using: .utf8), let compact = try? Self.decoder.decode(CompactTouchEvent.self, from: data) else { return nil }
        return decodeSingle(compact)
    }

    // MARK: - EDITOR DATA (bitmap, texte, forme)

    static func encodeEditorData(_ src: PBSEditorData) -> String {
        let compact = CompactEditorData(
            id: src.id, tp: typeCode(src.type), ac: typeCode(src.action), tc: src.textColor, cc: src.containerColor,
            tx: src.text, tw: Double(src.textWidth), th: Double(src.textHeight), l: Double(src.left), t: Double(src.top),
            px: Double(src.posX), py: Double(src.posY), bw: src.bitmapWidth, bh: src.bitmapHeight,
            bb: src.bitmapData?.base64EncodedString())
        return (try? Self.encoder.encode(compact)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decodeEditorData(_ json: String) -> PBSEditorData? {
        guard let data = json.data(using: .utf8), let c = try? Self.decoder.decode(CompactEditorData.self, from: data) else { return nil }
        var d = PBSEditorData()
        d.id = c.id
        d.type = typeString(c.tp)
        d.action = typeString(c.ac)
        d.textColor = c.tc
        d.containerColor = c.cc
        d.text = c.tx
        d.textWidth = CGFloat(c.tw)
        d.textHeight = CGFloat(c.th)
        d.left = CGFloat(c.l)
        d.top = CGFloat(c.t)
        d.posX = CGFloat(c.px)
        d.posY = CGFloat(c.py)
        d.bitmapWidth = c.bw
        d.bitmapHeight = c.bh
        d.bitmapData = c.bb.flatMap { Data(base64Encoded: $0) }
        return d
    }

    // MARK: - Détection automatique du type à la réception

    /// Port de `isTouchEvent` — un `CompactTouchEvent` a toujours `"a"` ET `"x0"`, un
    /// `CompactEditorData` jamais les deux ensemble (vérifié sur les deux structures fil).
    static func isTouchEvent(_ json: String) -> Bool {
        json.contains("\"a\":") && json.contains("\"x0\":")
    }

    private static func isCompactFormat(_ json: String) -> Bool {
        json.contains("\"x0\"")
    }

    // MARK: - BATCH (Message Graphic, module 14 — accumulation locale puis envoi différé)

    static func encodeTouchEventCompact(_ src: PBSTouchEvent) -> CompactTouchEvent { compact(from: src) }

    static func encodeTouchBatch(_ batch: [CompactTouchEvent]) -> String {
        (try? Self.encoder.encode(batch)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func decodeTouchBatch(_ json: String) -> [PBSTouchEvent] {
        guard let data = json.data(using: .utf8), let compacts = try? Self.decoder.decode([CompactTouchEvent].self, from: data) else { return [] }
        return compacts.map(decodeSingle)
    }

    /// Port de `decodeGraphicMessage` — point d'entrée unique pour décoder un message graphique
    /// stocké (`MessageLib.mgGraphic` substitué dans `message`, voir `ChatViewModel.onIncoming`) :
    /// UNIQUEMENT le format compact `[CompactTouchEvent]` — **le format "legacy"
    /// `MotionEventData[]` d'Android N'EST PAS repris** (aucune donnée existante sous cette forme
    /// ne peut exister côté iOS, ce format n'a jamais été émis par ce client ; conservé côté
    /// Android uniquement pour la compatibilité descendante avec d'anciens messages stockés avant
    /// l'introduction du format compact).
    static func decodeGraphicMessage(_ json: String?) -> [PBSTouchEvent] {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), isCompactFormat(trimmed) else { return [] }
        return decodeTouchBatch(trimmed)
    }

    // MARK: - Table de mapping type string ↔ byte court (port de `TYPE_TABLE`)

    private static let typeTable = ["drawPath", "text", "media1", "smile", "erasePath", "drawLine", "background", "media"]

    private static func typeCode(_ type: String?) -> Int {
        guard let type, let index = typeTable.firstIndex(of: type) else { return -1 }
        return index
    }

    private static func typeString(_ code: Int) -> String? {
        guard code >= 0, code < typeTable.count else { return nil }
        return typeTable[code]
    }

    // MARK: - Helpers

    private static func compact(from src: PBSTouchEvent) -> CompactTouchEvent {
        CompactTouchEvent(
            id: src.messageId, a: src.actionMasked, n: src.pointerCount, x0: Double(src.x[0]), y0: Double(src.y[0]),
            x1: src.pointerCount >= 2 ? Double(src.x[1]) : nil, y1: src.pointerCount >= 2 ? Double(src.y[1]) : nil,
            s: src.paintSize, c: src.paintColor, t: typeCode(src.type), sw: src.remoteScreenW, sh: src.remoteScreenH)
    }

    private static func decodeSingle(_ c: CompactTouchEvent) -> PBSTouchEvent {
        var d = PBSTouchEvent()
        d.messageId = c.id
        d.actionMasked = c.a
        d.pointerCount = c.n
        d.x = [CGFloat(c.x0), CGFloat(c.x1 ?? 0)]
        d.y = [CGFloat(c.y0), CGFloat(c.y1 ?? 0)]
        d.paintSize = c.s
        d.paintColor = c.c
        d.type = typeString(c.t)
        d.action = typeString(c.t)
        d.remoteScreenW = c.sw
        d.remoteScreenH = c.sh
        return d
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

/// Port de `CompactTouchEvent.java` (format fil, champs abrégés à dessein côté Android pour réduire
/// la taille des paquets envoyés à haute fréquence pendant le dessin).
struct CompactTouchEvent: Codable {
    var id: String
    var a: Int
    var n: Int
    var x0: Double
    var y0: Double
    var x1: Double?
    var y1: Double?
    var s: Int
    var c: Int
    var t: Int
    var sw: Int
    var sh: Int
}

/// Port de `CompactEditorData.java` (format fil) — `bb` (bitmap) encodé en Base64 côté Swift
/// (`Data.base64EncodedString`) : Android sérialise `byte[]` en Base64 via Gson par convention
/// (comportement par défaut de `TypeAdapter<byte[]>` de Gson, pas une supposition — c'est le
/// format Gson standard pour `byte[]`), donc compatible fil sans changement de format.
private struct CompactEditorData: Codable {
    var id: String
    var tp: Int
    var ac: Int
    var tc: Int
    var cc: Int
    var tx: String?
    var tw: Double
    var th: Double
    var l: Double
    var t: Double
    var px: Double
    var py: Double
    var bw: Int
    var bh: Int
    var bb: String?
}
