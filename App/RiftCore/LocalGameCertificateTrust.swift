import Foundation
import Security

/// The game's private CA issues long-lived localhost certificates. Apple's public
/// TLS lifetime policy rejects them, so validate X.509 trust plus the exact IP
/// and server-auth purpose. Callers must restrict this to 127.0.0.1:2999.
public enum LocalGameCertificateTrust {
    public static func evaluate(_ trust: SecTrust, anchor: SecCertificate) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let values = SecCertificateCopyValues(leaf,
                [kSecOIDSubjectAltName, kSecOIDExtendedKeyUsage] as CFArray, nil) as? [String: Any],
              let san = values[kSecOIDSubjectAltName as String] as? [String: Any],
              let names = san[kSecPropertyKeyValue as String] as? [[String: Any]],
              names.contains(where: {
                  ($0[kSecPropertyKeyLabel as String] as? String) == "IP Address" &&
                  ($0[kSecPropertyKeyValue as String] as? String) == "127.0.0.1"
              }),
              let eku = values[kSecOIDExtendedKeyUsage as String] as? [String: Any],
              let purposes = eku[kSecPropertyKeyValue as String] as? [Data],
              purposes.contains(Data([0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]))
        else { return false }

        // Retain signature, chain, and validity-date verification against only
        // the bundled Riot CA; never consult downloaded intermediate certificates.
        guard SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
