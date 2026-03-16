# Biometric Authentication Reference

## Table of Contents
1. [LAContext API](#lacontext-api)
2. [BiometricService Implementation](#biometricservice-implementation)
3. [Error Handling](#error-handling)
4. [Keychain + Biometrics Integration](#keychain--biometrics-integration)

## LAContext API

### Key Properties

| Property | Type | Purpose |
|----------|------|---------|
| `biometryType` | `LABiometryType` | `.faceID`, `.touchID`, `.opticID`, `.none` |
| `localizedFallbackTitle` | `String?` | Custom fallback button text (empty string hides it) |
| `localizedCancelTitle` | `String?` | Custom cancel button text |
| `interactionNotAllowed` | `Bool` | Suppress UI (for background checks) |
| `touchIDAuthenticationAllowableReuseDuration` | `TimeInterval` | Reuse window for recent auth |

### Policies

| Policy | Behavior |
|--------|----------|
| `.deviceOwnerAuthenticationWithBiometrics` | Biometrics only — fails if not available |
| `.deviceOwnerAuthentication` | Biometrics with passcode fallback — recommended for most flows |

### Required Info.plist

```xml
<key>NSFaceIDUsageDescription</key>
<string>We use Face ID to securely authenticate you</string>
```

This is **mandatory** for Face ID. Without it, the app crashes at runtime — no warning, no graceful error.

## BiometricService Implementation

```swift
import LocalAuthentication

final class BiometricService {

    enum BiometricType {
        case faceID
        case touchID
        case opticID
        case none
    }

    enum BiometricError: LocalizedError {
        case notAvailable
        case notEnrolled
        case lockedOut
        case cancelled
        case passcodeNotSet
        case failed
        case systemCancelled

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                "Biometric authentication is not available on this device"
            case .notEnrolled:
                "No biometrics are enrolled. Please set up Face ID or Touch ID in Settings"
            case .lockedOut:
                "Biometric authentication is locked. Please use your passcode to unlock"
            case .cancelled:
                "Authentication was cancelled"
            case .passcodeNotSet:
                "Please set a device passcode to use biometric authentication"
            case .failed:
                "Authentication failed. Please try again"
            case .systemCancelled:
                "Authentication was interrupted"
            }
        }
    }

    /// What biometric hardware is available
    var availableBiometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .none
        @unknown default: return .none
        }
    }

    /// Whether biometric auth is available right now
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Authenticate with biometrics only
    func authenticateWithBiometrics(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "" // Hide fallback button

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw mapError(error)
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch let laError as LAError {
            throw mapLAError(laError)
        }
    }

    /// Authenticate with biometrics + passcode fallback (recommended for most flows)
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw mapError(error)
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch let laError as LAError {
            throw mapLAError(laError)
        }
    }

    private func mapError(_ error: NSError?) -> BiometricError {
        guard let laError = error as? LAError else { return .notAvailable }
        return mapLAError(laError)
    }

    private func mapLAError(_ error: LAError) -> BiometricError {
        switch error.code {
        case .authenticationFailed: .failed
        case .userCancel: .cancelled
        case .userFallback: .cancelled
        case .systemCancel: .systemCancelled
        case .passcodeNotSet: .passcodeNotSet
        case .biometryNotAvailable: .notAvailable
        case .biometryNotEnrolled: .notEnrolled
        case .biometryLockout: .lockedOut
        case .appCancel: .cancelled
        default: .failed
        }
    }
}
```

### SwiftUI Integration

```swift
struct LoginView: View {
    let biometricService = BiometricService()
    @State private var isAuthenticated = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if isAuthenticated {
                Text("Welcome!")
            } else {
                Button {
                    Task { await authenticate() }
                } label: {
                    Label(
                        biometricButtonTitle,
                        systemImage: biometricButtonIcon
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private var biometricButtonTitle: String {
        switch biometricService.availableBiometricType {
        case .faceID: "Sign in with Face ID"
        case .touchID: "Sign in with Touch ID"
        case .opticID: "Sign in with Optic ID"
        case .none: "Sign in with Passcode"
        }
    }

    private var biometricButtonIcon: String {
        switch biometricService.availableBiometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock"
        }
    }

    private func authenticate() async {
        do {
            isAuthenticated = try await biometricService.authenticate(
                reason: "Sign in to your account"
            )
            errorMessage = nil
        } catch let error as BiometricService.BiometricError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }
    }
}
```

## Error Handling

### LAError Codes Reference

| Code | Meaning | User action |
|------|---------|-------------|
| `.authenticationFailed` | Invalid biometric | Retry or offer passcode |
| `.userCancel` | Tapped Cancel | Respect — don't immediately re-prompt |
| `.userFallback` | Tapped "Enter Password" | Show passcode/password input |
| `.systemCancel` | App went to background | Re-prompt when app becomes active |
| `.passcodeNotSet` | No device passcode | Guide to Settings |
| `.biometryNotAvailable` | No hardware support | Offer alternative auth |
| `.biometryNotEnrolled` | No biometrics set up | Guide to Settings > Face ID |
| `.biometryLockout` | Too many failures | Must use passcode to unlock biometry |
| `.appCancel` | App called invalidate() | Internal — handle gracefully |

### Best Practices

- **Never re-prompt immediately after `.userCancel`** — the user explicitly dismissed the dialog. Respect that. Wait for an explicit user action (tapping a button) to re-trigger.
- **Handle `.biometryLockout`** by falling back to `.deviceOwnerAuthentication` (which shows the passcode input). After successful passcode entry, biometry is automatically unlocked.
- **Always create a fresh `LAContext` for each evaluation** — reusing contexts can lead to unexpected state.
- **Use descriptive `localizedReason`** — this text appears in the system dialog. "Authenticate" is bad. "Sign in to your account" is good.

## Keychain + Biometrics Integration

The most secure pattern combines Keychain storage with biometric access control. The item is encrypted by the Secure Enclave and only released after successful biometric authentication.

```swift
import Security

// Save with biometric protection
func saveBiometricProtectedItem(data: Data, account: String) throws {
    var error: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .biometryCurrentSet,
        &error
    ) else {
        throw error!.takeRetainedValue() as Error
    }

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.app.biometric-protected",
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrAccessControl as String: accessControl
    ]

    // Delete first — SecItemUpdate doesn't work reliably with access control changes
    SecItemDelete([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.app.biometric-protected",
        kSecAttrAccount as String: account
    ] as CFDictionary)

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainManager.KeychainError.unexpectedStatus(status)
    }
}

// Read — system automatically shows biometric prompt
func readBiometricProtectedItem(account: String) throws -> Data {
    let context = LAContext()
    context.localizedReason = "Access your secure data"

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.app.biometric-protected",
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecUseAuthenticationContext as String: context
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
        throw KeychainManager.KeychainError.itemNotFound
    }

    return data
}
```

The system handles the biometric prompt automatically when `SecItemCopyMatching` is called for an item protected with `SecAccessControl`. You can pass a pre-authenticated `LAContext` via `kSecUseAuthenticationContext` to avoid double-prompting if you already authenticated the user.
