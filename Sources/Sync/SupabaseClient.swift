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
            let host = url.host, !host.isEmpty,
            host != "placeholder.supabase.co"
        else {
            fatalError("""
                SUPABASE_URL in Config/Secrets.xcconfig is missing or unparseable. \
                Remember "//" starts a comment in .xcconfig files — the scheme \
                separator must be written as https:$()/$()/your-project.supabase.co. \
                Use the bare project URL only (no /rest/v1 or /auth/v1 suffix — \
                the app appends those itself). See Secrets.xcconfig.example.
                """)
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

#if DEBUG
/// Avoids the macOS Keychain re-authorization prompt that fires on every
/// rebuild during local development — each ad-hoc-signed Debug build gets a
/// new code signature, so the OS treats it as a different app requesting
/// access to the previously Keychain-stored session. Release builds keep
/// the secure KeychainLocalStorage; this is dev-only.
struct UserDefaultsLocalStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: key)
    }

    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
#endif

enum SupabaseServices {
    static let auth = AuthClient(
        url: SupabaseConfig.url.appendingPathComponent("auth/v1"),
        headers: ["apikey": SupabaseConfig.anonKey],
        localStorage: {
            #if DEBUG
            UserDefaultsLocalStorage()
            #else
            KeychainLocalStorage()
            #endif
        }(),
        logger: nil
    )

    static let postgrest = PostgrestClient(
        url: SupabaseConfig.url.appendingPathComponent("rest/v1"),
        headers: ["apikey": SupabaseConfig.anonKey],
        logger: nil
    )
}
