import Foundation
import Security
import LocalAuthentication

enum CredentialVault {
    private static let service = "com.digitaldropkick.orbit.router"
    struct Login: Codable { let username: String; let password: String }
    static func store(_ login: Login, for endpoint: RouterEndpoint) throws {
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else {
            throw OrbitError.message("Set an iPhone passcode before saving router sign-in.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: endpoint.key]
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(login)
        item[kSecAttrAccessControl as String] = access
        var result = SecItemAdd(item as CFDictionary, nil)
        if result == errSecDuplicateItem {
            result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:try JSONEncoder().encode(login)] as CFDictionary)
        }
        guard result == errSecSuccess else { throw OrbitError.message("Connected, but iOS could not save the sign-in. You can sign in manually next time.") }
    }
    static func read(for endpoint: RouterEndpoint) throws -> Login? {
        let context = LAContext()
        context.localizedReason = "Unlock your saved router sign-in."
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: endpoint.key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw OrbitError.message("Saved sign-in was not unlocked. Tap Connect to try again, or enter your password.")
        }
        return try JSONDecoder().decode(Login.self, from: data)
    }
    static func forget(_ endpoint: RouterEndpoint) {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
                       kSecAttrAccount as String:endpoint.key] as CFDictionary)
    }
}
