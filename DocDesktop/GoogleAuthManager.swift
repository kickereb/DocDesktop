import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation

struct GoogleCredential: Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

struct GoogleOAuthSetupStatus {
    let isCallbackSchemeRegistered: Bool
    let callbackScheme: String
    let redirectURI: String

    var isReady: Bool {
        GoogleOAuthConfig.isConfigured && isCallbackSchemeRegistered
    }

    var missingSetupMessage: String? {
        guard GoogleOAuthConfig.isConfigured else {
            return "Add your Google OAuth client ID."
        }

        guard isCallbackSchemeRegistered else {
            return "Add URL scheme: \(callbackScheme)"
        }

        return nil
    }
}

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case missingAuthorizationCode
    case invalidAuthorizationResponse
    case tokenRequestFailed(Int, String?)
    case invalidTokenResponse
    case missingRefreshToken
    case missingPresentationWindow
    case callbackSchemeNotRegistered(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Google OAuth client ID and callback scheme first."
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .invalidAuthorizationResponse:
            return "Google returned an invalid authorization response."
        case .tokenRequestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Google token request failed with status \(statusCode): \(message)"
            }
            return "Google token request failed with status \(statusCode)."
        case .invalidTokenResponse:
            return "Google returned an invalid token response."
        case .missingRefreshToken:
            return "No saved Google refresh token was found."
        case .missingPresentationWindow:
            return "No window is available for sign-in."
        case .callbackSchemeNotRegistered(let scheme):
            return "Add this URL scheme in Xcode: \(scheme)"
        }
    }
}

@MainActor
@Observable
final class GoogleAuthManager {
    static let shared = GoogleAuthManager()

    private(set) var isSignedIn = false
    private(set) var statusText = "Not signed in"
    private(set) var errorMessage: String?

    var setupStatus: GoogleOAuthSetupStatus {
        GoogleOAuthSetupStatus(
            isCallbackSchemeRegistered: Self.isCallbackSchemeRegistered,
            callbackScheme: GoogleOAuthConfig.callbackScheme,
            redirectURI: GoogleOAuthConfig.redirectURI
        )
    }

    @ObservationIgnored private let keychain = KeychainManager()
    @ObservationIgnored private let refreshTokenAccount = "googleRefreshToken"
    @ObservationIgnored private let grantedScopesKey = "googleGrantedScopes"
    @ObservationIgnored private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    @ObservationIgnored private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    @ObservationIgnored private var currentCredential: GoogleCredential?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var presentationProvider: OAuthPresentationContextProvider?

    func restoreSession() async {
        do {
            guard hasRequiredScopes else {
                signOut()
                statusText = "Sign in again"
                errorMessage = "New Drive scope is required."
                return
            }

            let refreshToken = try keychain.read(account: refreshTokenAccount)
            currentCredential = try await refreshAccessToken(refreshToken: refreshToken)
            isSignedIn = true
            statusText = "Signed in"
            errorMessage = nil
        } catch KeychainError.itemNotFound {
            isSignedIn = false
            statusText = "Not signed in"
            errorMessage = nil
        } catch {
            isSignedIn = false
            statusText = "Sign-in restore failed"
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    func signIn(presentationWindow: NSWindow?) async {
        guard GoogleOAuthConfig.isConfigured else {
            errorMessage = GoogleAuthError.notConfigured.localizedDescription
            statusText = "Configuration needed"
            return
        }

        guard Self.isCallbackSchemeRegistered else {
            errorMessage = GoogleAuthError.callbackSchemeNotRegistered(GoogleOAuthConfig.callbackScheme).localizedDescription
            statusText = "Setup needed"
            return
        }

        guard let presentationWindow else {
            errorMessage = GoogleAuthError.missingPresentationWindow.localizedDescription
            statusText = "Sign-in failed"
            return
        }

        do {
            statusText = "Signing in"
            errorMessage = nil
            NSApp.activate(ignoringOtherApps: true)
            presentationWindow.makeKeyAndOrderFront(nil)

            let verifier = Self.makeCodeVerifier()
            let state = Self.randomURLSafeString(byteCount: 32)
            let authURL = try makeAuthorizationURL(codeChallenge: Self.codeChallenge(for: verifier), state: state)
            let callbackURL = try await authenticate(authURL: authURL, presentationWindow: presentationWindow)
            let code = try authorizationCode(from: callbackURL, expectedState: state)
            let credential = try await exchangeCodeForToken(code: code, codeVerifier: verifier)

            if let refreshToken = credential.refreshToken {
                try keychain.save(refreshToken, account: refreshTokenAccount)
            }
            UserDefaults.standard.set(GoogleOAuthConfig.scopes, forKey: grantedScopesKey)

            currentCredential = credential
            isSignedIn = true
            statusText = "Signed in"
            errorMessage = nil
        } catch {
            isSignedIn = false
            statusText = "Sign-in failed"
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    func validAccessToken() async throws -> String {
        if let currentCredential, currentCredential.expiresAt > Date().addingTimeInterval(60) {
            return currentCredential.accessToken
        }

        let refreshToken = try keychain.read(account: refreshTokenAccount)
        let credential = try await refreshAccessToken(refreshToken: refreshToken)
        currentCredential = credential
        isSignedIn = true
        statusText = "Signed in"
        errorMessage = nil
        return credential.accessToken
    }

    func signOut() {
        try? keychain.delete(account: refreshTokenAccount)
        UserDefaults.standard.removeObject(forKey: grantedScopesKey)
        currentCredential = nil
        webSession?.cancel()
        webSession = nil
        isSignedIn = false
        statusText = "Not signed in"
        errorMessage = nil
    }

    private func authenticate(authURL: URL, presentationWindow: NSWindow) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let provider = OAuthPresentationContextProvider(window: presentationWindow)
            presentationProvider = provider

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: GoogleOAuthConfig.callbackScheme
            ) { callbackURL, error in
                self.webSession = nil
                self.presentationProvider = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleAuthError.invalidAuthorizationResponse)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            guard session.start() else {
                webSession = nil
                presentationProvider = nil
                continuation.resume(throwing: GoogleAuthError.invalidAuthorizationResponse)
                return
            }
        }
    }

    private func makeAuthorizationURL(codeChallenge: String, state: String) throws -> URL {
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        return url
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        let queryItems = components.queryItems ?? []
        guard queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            throw GoogleAuthError.invalidAuthorizationResponse
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.missingAuthorizationCode
        }

        return code
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> GoogleCredential {
        let body = [
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ]

        return try await requestToken(body: body)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> GoogleCredential {
        let body = [
            "client_id": GoogleOAuthConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let credential = try await requestToken(body: body)
        return GoogleCredential(
            accessToken: credential.accessToken,
            refreshToken: refreshToken,
            expiresAt: credential.expiresAt
        )
    }

    private func requestToken(body: [String: String]) async throws -> GoogleCredential {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(from: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAuthError.invalidTokenResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            throw GoogleAuthError.tokenRequestFailed(httpResponse.statusCode, errorResponse?.displayMessage)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleCredential(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
    }

    private func formBody(from values: [String: String]) -> Data {
        let encoded = values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    private var hasRequiredScopes: Bool {
        let storedScopes = UserDefaults.standard.stringArray(forKey: grantedScopesKey) ?? []
        return Set(GoogleOAuthConfig.scopes).isSubset(of: Set(storedScopes))
    }

    private static var isCallbackSchemeRegistered: Bool {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }

        return urlTypes.contains { urlType in
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else { return false }
            return schemes.contains(GoogleOAuthConfig.callbackScheme)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "Network access failed. Enable App Sandbox Outgoing Connections."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private static func makeCodeVerifier() -> String {
        randomURLSafeString(byteCount: 64)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    var displayMessage: String? {
        [error, errorDescription]
            .compactMap { $0 }
            .joined(separator: ": ")
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}
