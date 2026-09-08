import Foundation

enum GoogleOAuthConfig {
    static let clientID = "178306346413-4pisgn7leup5r4839884l2dn9ec2f5u8.apps.googleusercontent.com"
    static let callbackScheme = "com.googleusercontent.apps.178306346413-4pisgn7leup5r4839884l2dn9ec2f5u8"
    static let redirectPath = "/oauth2redirect"

    static let scopes = [
        "https://www.googleapis.com/auth/documents",
        "https://www.googleapis.com/auth/drive.metadata.readonly",
        "https://www.googleapis.com/auth/drive.readonly"
    ]

    static var redirectURI: String {
        "\(callbackScheme):\(redirectPath)"
    }

    static var isConfigured: Bool {
        !clientID.contains("YOUR_GOOGLE_CLIENT_ID") && !callbackScheme.contains("YOUR_GOOGLE_CLIENT_ID")
    }
}
