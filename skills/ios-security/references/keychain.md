# Keychain Services Reference

## Table of Contents
1. [Core API](#core-api)
2. [KeychainManager Implementation](#keychainmanager-implementation)
3. [Access Control Options](#access-control-options)
4. [Keychain Sharing](#keychain-sharing)
5. [Jailbreak Detection](#jailbreak-detection)

## Core API

### SecItem Functions

All functions take `CFDictionary` (cast from `[String: Any]`). `kSecClass` is mandatory in every query.

| Function | Purpose | Key Return |
|----------|---------|------------|
| `SecItemAdd(_:_:)` | Add item | `errSecSuccess` or `errSecDuplicateItem` |
| `SecItemCopyMatching(_:_:)` | Retrieve item(s) | Data via `UnsafeMutablePointer<CFTypeRef?>` |
| `SecItemUpdate(_:_:)` | Update matching items | `errSecSuccess` |
| `SecItemDelete(_:)` | Delete matching items | `errSecSuccess` or `errSecItemNotFound` |

### kSecClass Types

| Constant | Use for |
|----------|---------|
| `kSecClassGenericPassword` | Tokens, passwords, arbitrary secrets |
| `kSecClassInternetPassword` | Server credentials (adds server, protocol, port) |
| `kSecClassCertificate` | X.509 certificates |
| `kSecClassKey` | Cryptographic keys |
| `kSecClassIdentity` | Private key + certificate combined |

### Essential Query Keys

| Key | Purpose |
|-----|---------|
| `kSecAttrAccount` | Account identifier (primary key with kSecAttrService) |
| `kSecAttrService` | Service identifier (primary key with kSecAttrAccount) |
| `kSecValueData` | The data to store (as `Data`) |
| `kSecReturnData` | `true` to return stored data |
| `kSecMatchLimit` | `kSecMatchLimitOne` or `kSecMatchLimitAll` |
| `kSecAttrAccessible` | When item is accessible |
| `kSecAttrAccessControl` | Fine-grained access (biometrics, passcode) |
| `kSecAttrAccessGroup` | Access group for sharing between apps |
| `kSecAttrSynchronizable` | `true` for iCloud Keychain sync |

### kSecAttrAccessible Options

| Constant | When Accessible | Migrates |
|----------|----------------|----------|
| `kSecAttrAccessibleWhenUnlocked` | While unlocked (DEFAULT) | Yes |
| `kSecAttrAccessibleAfterFirstUnlock` | After first unlock until restart | Yes |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | While unlocked, requires passcode | No |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | While unlocked | No |
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | After first unlock | No |

`ThisDeviceOnly` items don't migrate during backup/restore. `WhenPasscodeSet` items are deleted if the user removes their passcode.

## KeychainManager Implementation

This is the canonical wrapper. Use Codable generics so callers never touch Security framework.

```swift
import Foundation
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .duplicateItem: "Item already exists"
            case .itemNotFound: "Item not found"
            case .unexpectedStatus(let status): "Keychain error: \(status)"
            case .invalidData: "Invalid data format"
            }
        }
    }

    func save<T: Codable>(
        _ item: T,
        service: String,
        account: String,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) throws {
        let data = try JSONEncoder().encode(item)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Update existing item instead of failing
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(
                searchQuery as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read<T: Codable>(
        service: String,
        account: String,
        type: T.Type
    ) throws -> T {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func exists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Save with biometric protection
    func saveWithBiometricProtection<T: Codable>(
        _ item: T,
        service: String,
        account: String,
        biometricFlag: SecAccessControlCreateFlags = .biometryCurrentSet
    ) throws {
        let data = try JSONEncoder().encode(item)

        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            biometricFlag,
            &error
        ) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }

        // Delete existing item first (SecItemUpdate doesn't work well with access control changes)
        try? delete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

### Usage Examples

```swift
// Store a token
struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

let token = AuthToken(accessToken: "...", refreshToken: "...", expiresAt: .now.addingTimeInterval(3600))
try KeychainManager.shared.save(token, service: "com.myapp.auth", account: "current-user")

// Read it back
let stored = try KeychainManager.shared.read(
    service: "com.myapp.auth",
    account: "current-user",
    type: AuthToken.self
)

// Store with biometric protection
try KeychainManager.shared.saveWithBiometricProtection(
    token,
    service: "com.myapp.auth",
    account: "secure-token",
    biometricFlag: .biometryCurrentSet
)

// Delete on sign out
try KeychainManager.shared.delete(service: "com.myapp.auth", account: "current-user")
```

## Access Control Options

### SecAccessControlCreateFlags

| Flag | Behavior |
|------|----------|
| `.userPresence` | Biometrics OR passcode |
| `.biometryAny` | Any enrolled biometric (survives re-enrollment) |
| `.biometryCurrentSet` | Current biometric set only (more secure) |
| `.devicePasscode` | Device passcode required |
| `.or` / `.and` | Combine constraints |

Choose `.biometryCurrentSet` for highest security (item invalidated if user adds/removes a fingerprint). Choose `.biometryAny` for better UX (survives biometric changes).

## Keychain Sharing

### Setup
1. Enable "Keychain Sharing" capability in Xcode
2. Add access group identifier to entitlements
3. Use `kSecAttrAccessGroup` in queries

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.company.shared",
    kSecAttrAccount as String: "shared-token",
    kSecAttrAccessGroup as String: "AB123CDE45.com.company.shared",
    kSecValueData as String: tokenData
]
SecItemAdd(query as CFDictionary, nil)
```

Format: `<TeamID>.<GroupIdentifier>`. Both apps must use the same Team ID and declare the same access group.

## Jailbreak Detection

Combine multiple signals — no single check is definitive:

```swift
struct JailbreakDetector {
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return checkSuspiciousPaths()
            || checkCydiaURL()
            || checkWriteAccess()
            || checkDYLD()
        #endif
    }

    private static func checkSuspiciousPaths() -> Bool {
        [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
            "/private/var/lib/apt/", "/usr/bin/ssh",
            "/private/var/lib/cydia"
        ].contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func checkCydiaURL() -> Bool {
        guard let url = URL(string: "cydia://package/com.example.package") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func checkWriteAccess() -> Bool {
        let path = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch { return false }
    }

    private static func checkDYLD() -> Bool {
        let suspicious = ["SubstrateLoader", "SSLKillSwitch", "MobileSubstrate", "TweakInject"]
        for i in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(i) {
                let imageName = String(cString: name)
                if suspicious.contains(where: { imageName.contains($0) }) { return true }
            }
        }
        return false
    }
}
```

This is defense-in-depth. Sophisticated jailbreaks can bypass these checks, but they raise the bar. Use alongside other protections (certificate pinning, server-side validation).
