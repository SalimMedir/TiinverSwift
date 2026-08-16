import Foundation

/// Assouplissement de décodage pour les champs numériques/booléens du backend Tiinver.
///
/// **Cause racine confirmée du Home/Feed et du Profile vides** (2026-08-16) : le backend ne
/// garantit pas le type JSON natif des champs numériques (`id`, `likes`, `userId`, etc.) — déjà
/// connu et géré côté chemin JSON dynamique (`JSONValue.int(_:)`, qui accepte un `Int` OU une
/// chaîne numérique), mais jamais appliqué au chemin `Codable` strict utilisé par `FeedActivity`/
/// `User`. `Int.init(from:)` de la bibliothèque standard n'accepte QUE `Int`/`Double` JSON, jamais
/// une chaîne — dès qu'un item reçoit `"id": "123"` au lieu de `123`, `JSONDecoder` lève une
/// erreur pour CET ITEM, avalée silencieusement par le `compactMap` de `FeedRepository`
/// (ou par le `catch` de `ProfileRepository`), produisant une liste vide sans la moindre trace
/// d'erreur visible. Gson (Android) tolère nativement cette ambiguïté (`JsonReader.nextInt()`
/// accepte un jeton STRING numérique) — ce que `Codable` ne fait PAS par défaut, d'où la
/// divergence de comportement entre les deux plateformes malgré un JSON serveur identique.
extension KeyedDecodingContainer {
    /// `Int` obligatoire, tolérant `Int` JSON natif OU chaîne numérique (`"123"`).
    func decodeLenientInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let text = try? decode(String.self, forKey: key), let value = Int(text) { return value }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or numeric String for key \(key.stringValue)")
        )
    }

    /// `Int?` optionnel, même tolérance — absent/`null` renvoie `nil` plutôt que de lever.
    func decodeLenientIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let text = try? decode(String.self, forKey: key) { return Int(text) }
        return nil
    }

    /// `Double?` optionnel, même tolérance (soldes wallet notamment).
    func decodeLenientDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key) { return Double(text) }
        return nil
    }

    /// `Bool?` optionnel, tolérant `Bool` JSON natif, `"true"`/`"false"`, ou `"1"`/`"0"` — même
    /// classe de divergence que `Int`, Gson (`JsonReader.nextBoolean()`) acceptant un jeton STRING.
    func decodeLenientBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key) {
            if text == "true" || text == "1" { return true }
            if text == "false" || text == "0" { return false }
        }
        return nil
    }
}
