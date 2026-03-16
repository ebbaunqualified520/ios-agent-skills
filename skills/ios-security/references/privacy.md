# Privacy & Permissions Reference

## Table of Contents
1. [Privacy Manifests](#privacy-manifests)
2. [Required Reason APIs](#required-reason-apis)
3. [App Tracking Transparency](#app-tracking-transparency)
4. [Permission Handling](#permission-handling)
5. [App Transport Security](#app-transport-security)
6. [PermissionManager Implementation](#permissionmanager-implementation)

## Privacy Manifests

Since May 2024, any app using Required Reason APIs must include a `PrivacyInfo.xcprivacy` file. Apps without it are rejected during App Store review.

### File Structure

Create `PrivacyInfo.xcprivacy` in your app target (not as a separate file — add via Xcode > File > New > App Privacy):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Does the app track users? -->
    <key>NSPrivacyTracking</key>
    <false/>

    <!-- Tracking domains (only if NSPrivacyTracking is true) -->
    <key>NSPrivacyTrackingDomains</key>
    <array/>

    <!-- What data does the app collect? -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>

    <!-- Which Required Reason APIs does the app use? -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

### Common Data Types

| Constant | Data |
|----------|------|
| `NSPrivacyCollectedDataTypeEmailAddress` | Email |
| `NSPrivacyCollectedDataTypeName` | Name |
| `NSPrivacyCollectedDataTypePhoneNumber` | Phone |
| `NSPrivacyCollectedDataTypePhysicalAddress` | Address |
| `NSPrivacyCollectedDataTypeUserID` | User ID |
| `NSPrivacyCollectedDataTypeDeviceID` | Device ID |
| `NSPrivacyCollectedDataTypePreciseLocation` | GPS location |
| `NSPrivacyCollectedDataTypeCoarseLocation` | Approximate location |
| `NSPrivacyCollectedDataTypePhotos` | Photos |
| `NSPrivacyCollectedDataTypeHealthData` | Health data |
| `NSPrivacyCollectedDataTypeFitnessData` | Fitness data |

### Purposes

| Constant | Purpose |
|----------|---------|
| `NSPrivacyCollectedDataTypePurposeAppFunctionality` | Core app features |
| `NSPrivacyCollectedDataTypePurposeAnalytics` | Analytics |
| `NSPrivacyCollectedDataTypePurposeProductPersonalization` | Personalization |
| `NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising` | Advertising |
| `NSPrivacyCollectedDataTypePurposeDeveloperAdvertising` | Developer's own ads |

## Required Reason APIs

If your app uses any of these APIs, you must declare the reason in `PrivacyInfo.xcprivacy`.

| Category | API | Common Reason |
|----------|-----|---------------|
| UserDefaults | `UserDefaults`, `@AppStorage` | `CA92.1` — access app-specific preferences |
| File timestamp | `FileManager.attributesOfItem`, `URLResourceValues.contentModificationDate` | `C617.1` — file management in app container |
| System boot time | `ProcessInfo.systemUptime`, `mach_absolute_time` | `35F9.1` — measure elapsed time |
| Disk space | `URLResourceValues.volumeAvailableCapacity` | `E174.1` — display to user, `7D9E.1` — check before download |
| Active keyboards | `UITextInputMode.activeInputModes` | `3EC4.1` — custom keyboard functionality |

Almost every app uses `UserDefaults` → almost every app needs `CA92.1`.

## App Tracking Transparency

### When You Need It
- Using IDFA (advertising identifier)
- Third-party analytics/attribution SDKs that track across apps
- Any form of cross-app/cross-website user tracking

### Implementation

```swift
import AppTrackingTransparency
import AdSupport

func requestTrackingPermission() {
    // Must be called when app is in .active state
    guard UIApplication.shared.applicationState == .active else { return }

    ATTrackingManager.requestTrackingAuthorization { status in
        switch status {
        case .authorized:
            let idfa = ASIdentifierManager.shared().advertisingIdentifier
            // Send IDFA to analytics
        case .denied:
            // Use non-tracking analytics
            break
        case .notDetermined:
            break
        case .restricted:
            break
        @unknown default:
            break
        }
    }
}

// Check current status without prompting
func isTrackingAuthorized() -> Bool {
    ATTrackingManager.trackingAuthorizationStatus == .authorized
}
```

### Required Info.plist Key

```xml
<key>NSUserTrackingUsageDescription</key>
<string>We use this to provide personalized ads and measure ad effectiveness</string>
```

### Rules
- The prompt appears **once** per install (unless app is uninstalled and reinstalled)
- IDFA returns all zeros without authorization
- Call only when app is in `.active` state — otherwise the prompt silently fails
- Don't block the UI while waiting for the response
- Present one permission dialog at a time — don't stack ATT with other permissions

## Permission Handling

### All Info.plist Permission Keys

| Permission | Info.plist Key | Framework |
|------------|---------------|-----------|
| Camera | `NSCameraUsageDescription` | `AVCaptureDevice` |
| Microphone | `NSMicrophoneUsageDescription` | `AVCaptureDevice` |
| Photo Library (read) | `NSPhotoLibraryUsageDescription` | `PHPhotoLibrary` |
| Photo Library (add only) | `NSPhotoLibraryAddUsageDescription` | `PHPhotoLibrary` |
| Location (in use) | `NSLocationWhenInUseUsageDescription` | `CLLocationManager` |
| Location (always) | `NSLocationAlwaysAndWhenInUseUsageDescription` | `CLLocationManager` |
| Face ID | `NSFaceIDUsageDescription` | `LAContext` |
| Contacts | `NSContactsUsageDescription` | `CNContactStore` |
| Calendars (full) | `NSCalendarsFullAccessUsageDescription` | `EKEventStore` |
| Calendars (write only) | `NSCalendarsWriteOnlyAccessUsageDescription` | `EKEventStore` |
| Reminders (full) | `NSRemindersFullAccessUsageDescription` | `EKEventStore` |
| Bluetooth | `NSBluetoothAlwaysUsageDescription` | `CBCentralManager` |
| Health (share) | `NSHealthShareUsageDescription` | `HKHealthStore` |
| Health (update) | `NSHealthUpdateUsageDescription` | `HKHealthStore` |
| Motion | `NSMotionUsageDescription` | `CMMotionActivityManager` |
| Speech | `NSSpeechRecognitionUsageDescription` | `SFSpeechRecognizer` |
| Tracking | `NSUserTrackingUsageDescription` | `ATTrackingManager` |
| Local network | `NSLocalNetworkUsageDescription` | Bonjour |
| NFC | `NFCReaderUsageDescription` | `NFCNDEFReaderSession` |

### Permission Request Patterns

```swift
import AVFoundation
import Photos
import CoreLocation
import Contacts

// MARK: - Camera

func requestCameraAccess() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized: return true
    case .notDetermined:
        return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted:
        return false // Guide user to Settings
    @unknown default: return false
    }
}

// MARK: - Photo Library

func requestPhotoAccess() async -> PHAuthorizationStatus {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch status {
    case .notDetermined:
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    default:
        return status
    }
    // Handle .authorized, .limited, .denied, .restricted
}

// MARK: - Location

class LocationPermissionHandler: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    func requestWhenInUse() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume(returning: manager.authorizationStatus)
        continuation = nil
    }
}

// MARK: - Contacts

func requestContactsAccess() async throws -> Bool {
    let store = CNContactStore()
    return try await store.requestAccess(for: .contacts)
}
```

### Handling Denied Permissions

```swift
import SwiftUI

struct PermissionDeniedView: View {
    let permissionName: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("\(permissionName) Access Required")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

### Best Practices

- **Request at the moment of need** — not on app launch. User understands why when the context is clear.
- **Pre-permission dialog** — show a custom dialog explaining why before triggering the system prompt. This significantly increases grant rates.
- **Handle `.limited` for photos** — iOS 14+ lets users grant access to selected photos only. Use `PHPickerViewController` which doesn't require permission at all.
- **Use `PHPickerViewController` instead of requesting full photo library access** when you just need the user to pick photos.
- **Location: start with `.whenInUse`** — only request `.always` if you genuinely need background location. Apple scrutinizes this during review.

## App Transport Security

### Default Configuration (Secure — recommended)

ATS is enabled by default. All `URLSession` connections must use HTTPS with TLS 1.2+ and forward secrecy.

### Domain-Specific Exceptions

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <!-- Exception for a specific domain -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>legacy-api.example.com</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>

    <!-- Allow local network (for dev servers, IoT devices) -->
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

### ATS Keys Reference

| Key | Purpose | Default |
|-----|---------|---------|
| `NSAllowsArbitraryLoads` | Disable ATS globally (AVOID — requires App Review justification) | `false` |
| `NSAllowsArbitraryLoadsForMedia` | Allow HTTP for AV Foundation media | `false` |
| `NSAllowsArbitraryLoadsInWebContent` | Allow HTTP in WKWebView | `false` |
| `NSAllowsLocalNetworking` | Allow local (non-public) network connections | `false` |
| `NSExceptionDomains` | Per-domain exception rules | — |
| `NSExceptionMinimumTLSVersion` | Minimum TLS version | `TLSv1.2` |
| `NSExceptionRequiresForwardSecrecy` | Require PFS ciphers | `true` |
| `NSRequiresCertificateTransparency` | Require CT | `false` |

### Certificate Pinning

#### Info.plist-based (Simpler)

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSPinnedDomains</key>
    <dict>
        <key>api.example.com</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSPinnedCAIdentities</key>
            <array>
                <dict>
                    <key>SPKI-SHA256-BASE64</key>
                    <string>base64-encoded-public-key-hash</string>
                </dict>
            </array>
        </dict>
    </dict>
</dict>
```

#### Programmatic (URLSessionDelegate)

```swift
class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedKeyHashes: Set<String>

    init(pinnedKeyHashes: Set<String>) {
        self.pinnedKeyHashes = pinnedKeyHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get server's public key
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCertificate = certificateChain.first,
              let serverPublicKey = SecCertificateCopyKey(serverCertificate),
              let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey, nil) as Data?
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Hash and compare
        let serverKeyHash = SHA256.hash(data: serverPublicKeyData)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        if pinnedKeyHashes.contains(serverKeyHash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

Pin the **public key**, not the certificate. Public keys survive certificate renewal; certificates don't. Always have a backup pin (the next key in your rotation schedule) to avoid locking users out during key rotation.

## PermissionManager Implementation

```swift
import AVFoundation
import Photos
import CoreLocation
import UserNotifications

@Observable
final class PermissionManager {

    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case limited // Photos only
        case restricted
    }

    func cameraStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    func requestCamera() async -> PermissionStatus {
        guard cameraStatus() == .notDetermined else { return cameraStatus() }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
    }

    func photoLibraryStatus() -> PermissionStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .granted
        case .limited: .limited
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    func requestPhotoLibrary() async -> PermissionStatus {
        guard photoLibraryStatus() == .notDetermined else { return photoLibraryStatus() }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return switch status {
        case .authorized: .granted
        case .limited: .limited
        default: .denied
        }
    }

    func notificationStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .ephemeral: .granted
        @unknown default: .denied
        }
    }

    func requestNotifications(options: UNAuthorizationOptions = [.alert, .badge, .sound]) async -> PermissionStatus {
        guard await notificationStatus() == .notDetermined else { return await notificationStatus() }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
        return granted ? .granted : .denied
    }

    /// Open app Settings page — use when permission is denied
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
```
