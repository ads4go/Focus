import Foundation
import Auth
import PostgREST

/// Reads Supabase project URL/anon key from Info.plist, which Xcode fills in at
/// build time from Config/Secrets.xcconfig (see Secrets.xcconfig.example).
enum SupabaseConfig {
    static var url: URL {
        guard
            let string = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: string),
            url.host != "placeholder.supabase.co"
        else {
            fatalError("Set SUPABASE_URL in Config/Secrets.xcconfig — see Secrets.xcconfig.example")
        }
        return url
    }

    static var anonKey: String {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            key != "placeholder"
        else {
            fatalError("Set SUPABASE_ANON_KEY in Config/Secrets.xcconfig — see Secrets.xcconfig.example")
        }
        return key
    }
}

enum SupabaseServices {
    static let auth = AuthClient(
        url: SupabaseConfig.url.appendingPathComponent("auth/v1"),
        headers: ["apikey": SupabaseConfig.anonKey],
        localStorage: KeychainLocalStorage(),
        logger: nil
    )

    static let postgrest = PostgrestClient(
        url: SupabaseConfig.url.appendingPathComponent("rest/v1"),
        headers: ["apikey": SupabaseConfig.anonKey],
        logger: nil
    )
}
