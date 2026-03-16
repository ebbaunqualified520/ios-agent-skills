# Authentication Patterns Reference

## Table of Contents
1. [Sign in with Apple](#sign-in-with-apple)
2. [OAuth2 with ASWebAuthenticationSession](#oauth2)
3. [Token Management](#token-management)
4. [AuthManager Implementation](#authmanager-implementation)

## Sign in with Apple

### Required Setup
1. Enable "Sign in with Apple" capability in Xcode
2. Add `NSFaceIDUsageDescription` to Info.plist if using biometric re-auth
3. Framework: `AuthenticationServices`

### SwiftUI Implementation

```swift
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = randomNonceString()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            // Store raw nonce for server-side verification
            currentNonce = nonce
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                handleAuthorization(authorization)
            case .failure(let error):
                handleError(error)
            }
        }
        .signInWithAppleButtonStyle(
            colorScheme == .dark ? .white : .black
        )
        .frame(height: 50)
    }

    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        let userID = credential.user                      // Stable across sessions
        let email = credential.email                       // Only on FIRST sign-in
        let fullName = credential.fullName                 // Only on FIRST sign-in
        let identityToken = credential.identityToken       // JWT for server validation
        let authorizationCode = credential.authorizationCode // Exchange on server

        // Store userID in Keychain immediately — it's the primary identifier
        try? KeychainManager.shared.save(
            userID,
            service: "com.app.auth",
            account: "apple-user-id"
        )

        // Send identityToken + authorizationCode to your server
        // Server validates JWT, exchanges code, creates session
    }

    private func handleError(_ error: Error) {
        guard let authError = error as? ASAuthorizationError else { return }
        switch authError.code {
        case .canceled: break // User tapped Cancel — don't show error
        case .failed: showError("Sign in failed. Please try again.")
        case .invalidResponse: showError("Invalid response from Apple.")
        case .notHandled: showError("Sign in was not handled.")
        case .notInteractive: break // Non-interactive context
        case .unknown: showError("An unknown error occurred.")
        @unknown default: break
        }
    }
}
```

### UIKit Implementation

```swift
import AuthenticationServices

class LoginViewController: UIViewController {

    private var currentNonce: String?

    func startSignInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension LoginViewController: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        // Same handling as SwiftUI version
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // Same error handling
    }
}

extension LoginViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window!
    }
}
```

### Credential State Checking

Check on every app launch — the user may have revoked access via Apple ID settings.

```swift
func checkAppleIDCredentialState() async {
    guard let userID: String = try? KeychainManager.shared.read(
        service: "com.app.auth",
        account: "apple-user-id",
        type: String.self
    ) else { return }

    let provider = ASAuthorizationAppleIDProvider()
    do {
        let state = try await provider.credentialState(forUserID: userID)
        switch state {
        case .authorized:
            break // User is still authorized
        case .revoked:
            signOut() // User revoked — must sign out
        case .notFound:
            signOut() // Credential gone — sign out
        case .transferred:
            break // App transferred to new dev team
        @unknown default:
            break
        }
    } catch {
        // Network error — don't sign out, try again later
    }
}
```

### Nonce Generation

Always use a cryptographic nonce to prevent replay attacks.

```swift
func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    var randomBytes = [UInt8](repeating: 0, count: length)
    let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    precondition(errorCode == errSecSuccess, "Failed to generate random bytes")
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    return String(randomBytes.map { charset[Int($0) % charset.count] })
}

func sha256(_ input: String) -> String {
    let data = input.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

## OAuth2

### ASWebAuthenticationSession

This is the correct way to do OAuth2 on iOS. It uses a secure system browser — never use WKWebView for OAuth (it can't access Safari cookies and is vulnerable to phishing).

```swift
import AuthenticationServices

class OAuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {

    func authenticate(
        authURL: URL,
        callbackScheme: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true // Don't share cookies with Safari
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
```

### Building the Auth URL

```swift
func buildAuthURL(
    authorizeEndpoint: String,
    clientID: String,
    redirectURI: String,
    scopes: [String],
    state: String
) -> URL? {
    var components = URLComponents(string: authorizeEndpoint)!
    components.queryItems = [
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        URLQueryItem(name: "state", value: state) // CSRF protection
    ]
    return components.url
}
```

### URL Scheme Registration

Register your callback URL scheme in Info.plist:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.company.myapp</string>
    </dict>
</array>
```

## Token Management

### TokenManager Implementation

```swift
final class TokenManager {
    private let keychain = KeychainManager.shared
    private let service = "com.app.auth"

    struct TokenPair: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    var isAuthenticated: Bool {
        (try? currentTokens()) != nil
    }

    var isTokenExpired: Bool {
        guard let tokens = try? currentTokens() else { return true }
        return tokens.expiresAt < Date()
    }

    func storeTokens(_ tokens: TokenPair) throws {
        try keychain.save(tokens, service: service, account: "tokens")
    }

    func currentTokens() throws -> TokenPair {
        try keychain.read(service: service, account: "tokens", type: TokenPair.self)
    }

    func clearTokens() throws {
        try keychain.delete(service: service, account: "tokens")
    }

    /// Get a valid access token, refreshing if expired
    func validAccessToken() async throws -> String {
        let tokens = try currentTokens()

        if tokens.expiresAt > Date().addingTimeInterval(60) {
            // Token valid for at least 60 more seconds
            return tokens.accessToken
        }

        // Token expired or expiring soon — refresh
        return try await refreshAccessToken(using: tokens.refreshToken)
    }

    private func refreshAccessToken(using refreshToken: String) async throws -> String {
        // Call your server's token refresh endpoint
        let request = buildRefreshRequest(refreshToken: refreshToken)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            let newTokens = try JSONDecoder().decode(TokenPair.self, from: data)
            try storeTokens(newTokens)
            return newTokens.accessToken
        case 401:
            // Refresh token expired — force re-authentication
            try clearTokens()
            throw AuthError.sessionExpired
        default:
            throw AuthError.networkError
        }
    }

    private func buildRefreshRequest(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.example.com/auth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])
        return request
    }
}
```

### Authenticated API Client Pattern

```swift
final class APIClient {
    private let tokenManager: TokenManager
    private let session = URLSession.shared

    init(tokenManager: TokenManager) {
        self.tokenManager = tokenManager
    }

    func authenticatedRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var authedRequest = request
        let token = try await tokenManager.validAccessToken()
        authedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: authedRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        if httpResponse.statusCode == 401 {
            // Token was valid but server rejected — force refresh and retry once
            try tokenManager.clearTokens()
            throw AuthError.sessionExpired
        }

        return (data, response)
    }
}
```

## AuthManager Implementation

Orchestrates all authentication flows in one place.

```swift
import AuthenticationServices

@Observable
final class AuthManager {
    private(set) var isAuthenticated = false
    private(set) var currentUser: User?

    private let tokenManager = TokenManager()
    private let biometricService = BiometricService()
    private let keychainManager = KeychainManager.shared

    init() {
        isAuthenticated = tokenManager.isAuthenticated
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            throw AuthError.invalidCredential
        }

        // Send to server for validation
        let tokens = try await exchangeAppleToken(identityToken)
        try tokenManager.storeTokens(tokens)

        // Store Apple user ID for credential state checking
        try keychainManager.save(
            credential.user,
            service: "com.app.auth",
            account: "apple-user-id"
        )

        isAuthenticated = true
    }

    // MARK: - Biometric Re-auth

    func authenticateWithBiometrics() async throws {
        guard tokenManager.isAuthenticated else {
            throw AuthError.authenticationRequired
        }
        _ = try await biometricService.authenticate(
            reason: "Verify your identity"
        )
    }

    // MARK: - Sign Out

    func signOut() throws {
        try tokenManager.clearTokens()
        try keychainManager.delete(service: "com.app.auth", account: "apple-user-id")
        isAuthenticated = false
        currentUser = nil
    }

    // MARK: - App Launch

    func checkAuthState() async {
        // Check Apple credential state
        if let userID: String = try? keychainManager.read(
            service: "com.app.auth",
            account: "apple-user-id",
            type: String.self
        ) {
            let provider = ASAuthorizationAppleIDProvider()
            if let state = try? await provider.credentialState(forUserID: userID),
               state == .revoked {
                try? signOut()
                return
            }
        }

        // Validate token
        isAuthenticated = tokenManager.isAuthenticated && !tokenManager.isTokenExpired
    }

    private func exchangeAppleToken(_ token: String) async throws -> TokenManager.TokenPair {
        // POST to your server — server validates JWT with Apple, creates session
        var request = URLRequest(url: URL(string: "https://api.example.com/auth/apple")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["identity_token": token])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenManager.TokenPair.self, from: data)
    }
}
```
