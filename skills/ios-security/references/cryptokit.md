# CryptoKit Reference

## Table of Contents
1. [Hashing](#hashing)
2. [Symmetric Encryption](#symmetric-encryption)
3. [HMAC](#hmac)
4. [Asymmetric Keys](#asymmetric-keys)
5. [Key Agreement](#key-agreement)
6. [Secure Enclave](#secure-enclave)
7. [CryptoService Implementation](#cryptoservice-implementation)

## Hashing

```swift
import CryptoKit

let data = "Hello, World!".data(using: .utf8)!

// SHA-256 (recommended default)
let sha256 = SHA256.hash(data: data)
let hexString = sha256.compactMap { String(format: "%02x", $0) }.joined()

// SHA-384, SHA-512
let sha384 = SHA384.hash(data: data)
let sha512 = SHA512.hash(data: data)

// Hash streaming data
var hasher = SHA256()
hasher.update(data: chunk1)
hasher.update(data: chunk2)
let digest = hasher.finalize()
```

Never use SHA-1 or MD5 for security. They're broken. SHA-256 is the default choice.

## Symmetric Encryption

### AES-GCM (Recommended)

AES-GCM provides authenticated encryption — both confidentiality and integrity in one operation.

```swift
// Generate key
let key = SymmetricKey(size: .bits256)  // .bits128, .bits192, .bits256

// Encrypt
let plaintext = "Secret message".data(using: .utf8)!
let sealedBox = try AES.GCM.seal(plaintext, using: key)
let combined = sealedBox.combined!  // nonce (12 bytes) + ciphertext + tag (16 bytes)

// Decrypt
let sealedBoxFromData = try AES.GCM.SealedBox(combined: combined)
let decrypted = try AES.GCM.open(sealedBoxFromData, using: key)
let message = String(data: decrypted, encoding: .utf8)!

// With custom nonce (rarely needed — auto-generated is safer)
let nonce = AES.GCM.Nonce()
let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
```

### ChaChaPoly (Alternative)

Same API as AES-GCM. Better software performance on devices without AES hardware acceleration (rare for iOS, but useful for macOS).

```swift
let sealed = try ChaChaPoly.seal(plaintext, using: key)
let decrypted = try ChaChaPoly.open(sealed, using: key)
```

### SymmetricKey from Password

```swift
// Derive key from password using HKDF
let passwordData = "user-password".data(using: .utf8)!
let salt = "unique-salt".data(using: .utf8)!

let key = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: passwordData),
    salt: salt,
    info: Data("encryption-key".utf8),
    outputByteCount: 32
)
```

### Key Storage

Never store `SymmetricKey` in UserDefaults. Two options:

1. **Keychain** — store key bytes via `KeychainManager`
2. **Derive from user input** — re-derive using HKDF each time (no storage needed)

```swift
// Store key in Keychain
let keyData = key.withUnsafeBytes { Data($0) }
try KeychainManager.shared.save(keyData, service: "com.app.crypto", account: "encryption-key")

// Restore key from Keychain
let storedData: Data = try KeychainManager.shared.read(
    service: "com.app.crypto",
    account: "encryption-key",
    type: Data.self
)
let restoredKey = SymmetricKey(data: storedData)
```

## HMAC

Use HMAC to verify data integrity and authenticity.

```swift
let key = SymmetricKey(size: .bits256)

// Create authentication code
let authCode = HMAC<SHA256>.authenticationCode(for: data, using: key)
let authCodeData = Data(authCode)

// Verify
let isValid = HMAC<SHA256>.isValidAuthenticationCode(authCodeData, authenticating: data, using: key)
```

HMAC is not encryption — it doesn't hide data, it proves the data hasn't been tampered with and was created by someone with the key.

## Asymmetric Keys

### Signing (P256 / P384 / P521)

```swift
// Generate key pair
let privateKey = P256.Signing.PrivateKey()
let publicKey = privateKey.publicKey

// Sign
let signature = try privateKey.signature(for: data)

// Verify
let isValid = publicKey.isValidSignature(signature, for: data)

// Export for transmission
let publicKeyRaw = publicKey.rawRepresentation     // Data — compact
let publicKeyPEM = publicKey.pemRepresentation     // String — interoperable
let publicKeyDER = publicKey.derRepresentation     // Data — X.509

// Import
let importedKey = try P256.Signing.PublicKey(rawRepresentation: publicKeyRaw)
let importedPEM = try P256.Signing.PublicKey(pemRepresentation: publicKeyPEM)
let importedDER = try P256.Signing.PublicKey(derRepresentation: publicKeyDER)

// Private key export (handle with extreme care)
let privateKeyRaw = privateKey.rawRepresentation
let restoredPrivate = try P256.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
```

### Curve25519

```swift
// Signing
let key = Curve25519.Signing.PrivateKey()
let signature = try key.signature(for: data)
let isValid = key.publicKey.isValidSignature(signature, for: data)

// Key Agreement
let keyAgreement = Curve25519.KeyAgreement.PrivateKey()
```

### When to Use What

| Algorithm | Use for |
|-----------|---------|
| P256 | Default choice. Secure Enclave compatible. Widely supported |
| P384 | Higher security margin (rarely needed) |
| P521 | Maximum security (performance overhead, rarely needed) |
| Curve25519 | High performance, modern. Not Secure Enclave compatible |

## Key Agreement

Derive a shared symmetric key from two asymmetric key pairs (Diffie-Hellman).

```swift
// Alice
let alicePrivate = P256.KeyAgreement.PrivateKey()
let alicePublic = alicePrivate.publicKey

// Bob
let bobPrivate = P256.KeyAgreement.PrivateKey()
let bobPublic = bobPrivate.publicKey

// Both derive the same shared secret
let sharedSecret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPublic)

// Derive a symmetric key
let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
    using: SHA256.self,
    salt: "protocol-salt".data(using: .utf8)!,
    sharedInfo: Data(),
    outputByteCount: 32
)

// Use for encryption
let encrypted = try AES.GCM.seal(message, using: symmetricKey)
```

## Secure Enclave

The Secure Enclave is dedicated security hardware. Keys generated here never leave the chip — even the OS can't extract them. Only P256 is available.

```swift
// Generate key in Secure Enclave
let privateKey = try SecureEnclave.P256.Signing.PrivateKey()

// Sign data — private key never leaves hardware
let signature = try privateKey.signature(for: data)

// Verify with public key (can be exported)
let isValid = privateKey.publicKey.isValidSignature(signature, for: data)

// Key Agreement via Secure Enclave
let keyAgreementKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
let sharedSecret = try keyAgreementKey.sharedSecretFromKeyAgreement(with: otherPublicKey)

// Persist the key across app launches
// Store dataRepresentation in Keychain — this is an OPAQUE BLOB, not the private key itself
let keyData = privateKey.dataRepresentation
try KeychainManager.shared.save(keyData, service: "com.app.se", account: "signing-key")

// Restore
let storedData: Data = try KeychainManager.shared.read(
    service: "com.app.se", account: "signing-key", type: Data.self
)
let restoredKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: storedData)
```

### Secure Enclave with Access Control

Combine Secure Enclave with biometric protection:

```swift
let accessControl = SecAccessControl.create(
    accessibility: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    flags: .biometryCurrentSet
)

let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
    accessControl: accessControl
)
// Signing will now require biometric auth
```

### Limitations
- **P256 only** — no P384, P521, or Curve25519
- **Cannot export private key** — `dataRepresentation` is an opaque handle, not raw key material
- **Requires hardware** — not available in Simulator (use `SecureEnclave.isAvailable` to check)
- **Access control optional** — but recommended for sensitive operations

## CryptoService Implementation

```swift
import CryptoKit
import Foundation

final class CryptoService {

    enum CryptoError: Error {
        case encryptionFailed
        case decryptionFailed
        case keyGenerationFailed
        case secureEnclaveUnavailable
    }

    // MARK: - Hashing

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    func sha256(_ string: String) -> String {
        sha256(string.data(using: .utf8)!)
    }

    // MARK: - Symmetric Encryption

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func generateSymmetricKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    // MARK: - HMAC

    func hmac(for data: Data, using key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    func verifyHMAC(_ mac: Data, for data: Data, using key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: key)
    }

    // MARK: - Secure Enclave

    func isSecureEnclaveAvailable() -> Bool {
        SecureEnclave.isAvailable
    }

    func generateSecureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else {
            throw CryptoError.secureEnclaveUnavailable
        }
        return try SecureEnclave.P256.Signing.PrivateKey()
    }

    func sign(_ data: Data, with key: SecureEnclave.P256.Signing.PrivateKey) throws -> Data {
        let signature = try key.signature(for: data)
        return signature.rawRepresentation
    }
}
```
