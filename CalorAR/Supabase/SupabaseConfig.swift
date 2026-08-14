import Foundation
import Supabase

/// Reads the Supabase connection details that Config/Base.xcconfig injects into
/// the generated Info.plist at build time.
///
/// Deliberately non-fatal when unconfigured: a fresh clone has no
/// Config/Secrets.xcconfig, and the app should show a clear explanation rather
/// than crash on launch.
enum SupabaseConfig {

    enum ConfigError: LocalizedError {
        case missingURL
        case invalidURL(String)
        case missingPublishableKey

        var errorDescription: String? {
            switch self {
            case .missingURL:
                return "Falta SupabaseURL en el Info.plist."
            case .invalidURL(let raw):
                return "SupabaseURL no es una URL válida: \(raw)"
            case .missingPublishableKey:
                // The most likely cause by far, so name the fix directly.
                return """
                    Falta la clave de Supabase. Copiá \
                    Config/Secrets.example.xcconfig a Config/Secrets.xcconfig \
                    y completá SUPABASE_PUBLISHABLE_KEY.
                    """
            }
        }
    }

    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func makeClient() throws -> SupabaseClient {
        guard let rawURL = infoValue("SupabaseURL") else {
            throw ConfigError.missingURL
        }
        guard let url = URL(string: rawURL), url.host != nil else {
            throw ConfigError.invalidURL(rawURL)
        }
        guard let key = infoValue("SupabasePublishableKey") else {
            throw ConfigError.missingPublishableKey
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    /// Whether the build carries everything needed to reach Supabase.
    static var isConfigured: Bool {
        (try? makeClient()) != nil
    }

    /// Host only — safe to display. Never surface the key in UI or logs.
    static var displayHost: String? {
        infoValue("SupabaseURL").flatMap { URL(string: $0)?.host }
    }
}
