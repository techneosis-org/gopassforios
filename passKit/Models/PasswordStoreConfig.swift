//
//  PasswordStoreConfig.swift
//  passKit
//

import Foundation

/// The configuration of a single mounted password store.
///
/// gopass mounts several stores at once, each backed by its own git remote and
/// its own set of recipients. One of these describes one such mount; the app
/// keeps a list of them and presents their contents as a single tree.
public struct PasswordStoreConfig: Codable, Equatable, Identifiable {
    /// Stable identity of the store. Used to derive the on-disk location and
    /// the keychain entries, so it must not change once the store is cloned.
    public let id: UUID

    /// The mount name, e.g. `personal`. Shown as the root of this store's
    /// subtree and used to disambiguate entries with the same relative path.
    public var name: String

    public var gitURL: URL
    public var branchName: String
    public var authenticationMethod: GitAuthenticationMethod
    public var username: String

    /// Identifier of the single store that predates multi-store support.
    /// Entries carrying it resolve against `Globals.repositoryURL` rather than
    /// a per-store checkout, so the existing clone keeps working untouched.
    public static let legacyStoreID = "legacy"

    public init(
        name: String,
        gitURL: URL,
        id: UUID = UUID(),
        branchName: String = "main",
        authenticationMethod: GitAuthenticationMethod = .password,
        username: String = "git"
    ) {
        self.id = id
        self.name = name
        self.gitURL = gitURL
        self.branchName = branchName
        self.authenticationMethod = authenticationMethod
        self.username = username
    }

    /// Where this store is checked out. Keyed by `id` rather than `name` so
    /// that renaming a mount does not orphan its working copy.
    public var localURL: URL {
        Globals.storesURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Keychain key holding the git password for this store.
    public var gitPasswordKey: String {
        "\(Globals.gitPassword).\(id.uuidString)"
    }

    /// Keychain key holding the SSH key passphrase for this store.
    public var gitSSHPrivateKeyPassphraseKey: String {
        "\(Globals.gitSSHPrivateKeyPassphrase).\(id.uuidString)"
    }
}

// Coding is written out rather than synthesised because `GitAuthenticationMethod`
// is not `Codable`, and making it so would be worse than this: it already
// conforms to `DefaultsSerializable` as a `RawRepresentable`, and
// `DefaultsKeys.swift` declares `Bridge` typealiases for both the `Codable` and
// the `RawRepresentable` case. A type matching both leaves `Bridge` ambiguous.
public extension PasswordStoreConfig {
    private enum CodingKeys: String, CodingKey {
        case id, name, gitURL, branchName, authenticationMethod, username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMethod = try container.decode(String.self, forKey: .authenticationMethod)
        guard let method = GitAuthenticationMethod(rawValue: rawMethod) else {
            throw DecodingError.dataCorruptedError(
                forKey: .authenticationMethod,
                in: container,
                debugDescription: "unknown git authentication method: \(rawMethod)"
            )
        }
        self.init(
            name: try container.decode(String.self, forKey: .name),
            gitURL: try container.decode(URL.self, forKey: .gitURL),
            id: try container.decode(UUID.self, forKey: .id),
            branchName: try container.decode(String.self, forKey: .branchName),
            authenticationMethod: method,
            username: try container.decode(String.self, forKey: .username)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(gitURL, forKey: .gitURL)
        try container.encode(branchName, forKey: .branchName)
        try container.encode(authenticationMethod.rawValue, forKey: .authenticationMethod)
        try container.encode(username, forKey: .username)
    }
}
