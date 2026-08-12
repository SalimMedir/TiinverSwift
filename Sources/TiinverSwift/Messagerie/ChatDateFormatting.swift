import Foundation

/// Port de `Utils/StringUtils.getDate(Context, long)`/`getTime(long)` (lu en entier) — formatage
/// d'horodatage pour les bulles de chat et séparateurs de date.
enum ChatDateFormatting {
    /// Port de `getTime(long timeMs)` — heure 12h `"hh:mm a. m./p. m."` (`Calendar.HOUR`, PAS
    /// `HOUR_OF_DAY` : 0-11, reproduit avec `dateFormat("hh:mm")`), suffixe français " a. m."/
    /// " p. m." recopié tel quel (pas de re-localisation, l'original ne dépend pas de la langue
    /// système pour ce suffixe).
    static func time(fromStampMillis stampMillis: String?) -> String {
        guard let ms = stampMillis.flatMap(Double.init) else { return "" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let hourMinute = formatter.string(from: date)
        let isPM = Calendar.current.component(.hour, from: date) >= 12
        return hourMinute + (isPM ? " p. m." : " a. m.")
    }

    /// Port de `getDate(Context, long timeMs)` — "Aujourd'hui"/"Hier" si applicable, sinon
    /// `"yyyy MM dd"` (format brut de l'original, pas re-stylé).
    static func date(fromStampMillis stampMillis: String?) -> String {
        guard let ms = stampMillis.flatMap(Double.init) else { return "" }
        let messageDate = Date(timeIntervalSince1970: ms / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(messageDate) { return "Aujourd'hui" } // R.string.today
        if calendar.isDateInYesterday(messageDate) { return "Hier" } // R.string.yesterday
        let components = calendar.dateComponents([.year, .month, .day], from: messageDate)
        return String(format: "%d %02d %02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
