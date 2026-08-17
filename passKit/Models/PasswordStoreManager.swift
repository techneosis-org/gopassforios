//
//  PasswordStoreManager.swift
//  passKit
//

import Foundation

/// Vends the `PasswordStore` for each configured mount.
///
/// Instances are cached because creating one opens the git repository at its
/// checkout; handing out a fresh object per call would reopen the same
/// repository repeatedly and leave callers holding stores that disagree about
/// its state.
public final class PasswordStoreManager {
    public static let shared = PasswordStoreManager()

    private let registry: PasswordStoreRegistry
    private let legacyStore: () -> PasswordStore
    private var cache: [String: PasswordStore] = [:]

    /// The legacy store arrives as an autoclosure so that constructing a
    /// manager does not construct PasswordStore.shared. Building that singleton
    /// runs a one-time key migration against the shared keychain, which is a
    /// side effect no caller — least of all a test — should trigger merely by
    /// asking which stores exist.
    public init(
        registry: PasswordStoreRegistry = .shared,
        legacyStore: @escaping @autoclosure () -> PasswordStore = PasswordStore.shared
    ) {
        self.registry = registry
        self.legacyStore = legacyStore
    }

    /// The store backing a configured mount.
    public func store(for config: PasswordStoreConfig) -> PasswordStore {
        let id = config.id.uuidString
        if let existing = cache[id] {
            return existing
        }
        let store = PasswordStore(url: config.localURL, storeID: id)
        cache[id] = store
        return store
    }

    /// Every configured mount, in the order they were added.
    public var stores: [PasswordStore] {
        registry.configs.map { store(for: $0) }
    }

    /// The store an entry belongs to, or nil if its mount is no longer
    /// configured — which happens between a store being removed and its
    /// entries being cleared out.
    public func store(withID id: String) -> PasswordStore? {
        if id == PasswordStoreConfig.legacyStoreID {
            return legacyStore()
        }
        guard let uuid = UUID(uuidString: id), let config = registry.config(withID: uuid) else {
            return nil
        }
        return store(for: config)
    }

    /// Every store, the original one first, then the configured mounts.
    public var allStores: [PasswordStore] {
        [legacyStore()] + stores
    }

    /// The store an entry was read from.
    public func store(for entity: PasswordEntity) -> PasswordStore? {
        store(withID: entity.store)
    }

    /// Mount name of a store, or nil if it is no longer configured.
    public func name(forStore id: String) -> String? {
        if id == PasswordStoreConfig.legacyStoreID {
            return Defaults.legacyStoreName
        }
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }
        return registry.config(withID: uuid)?.name
    }

    /// How an entry is named across the whole app: its mount, then its path
    /// within that mount. Paths repeat between stores, mount names do not, so
    /// this is what anything holding a reference to a password should use —
    /// AutoFill records it, and it is what the user sees.
    public func qualifiedPath(for entity: PasswordEntity) -> String? {
        guard let name = name(forStore: entity.store) else {
            return nil
        }
        return "\(name)/\(entity.path)"
    }

    /// Resolves a qualified path back to its store and entry.
    public func resolve(qualifiedPath: String) -> (store: PasswordStore, entity: PasswordEntity)? {
        let parts = qualifiedPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let mount = String(parts[0])
        let path = String(parts[1])
        for store in allStores where name(forStore: store.storeID) == mount {
            if let entity = store.fetchPasswordEntity(with: path) {
                return (store, entity)
            }
        }
        return nil
    }

    /// Decrypts whatever a stored identifier refers to, in the store that owns
    /// it. Identifiers written before stores existed are bare paths, so those
    /// still resolve against the original store — otherwise every AutoFill
    /// entry saved by an earlier version would stop working after an upgrade.
    public func decrypt(identifier: String, keyID: String? = nil, requestPGPKeyPassphrase: @escaping (String) -> String) throws -> Password {
        if let (store, entity) = resolve(qualifiedPath: identifier) {
            return try decrypt(entity, in: store, keyID: keyID, requestPGPKeyPassphrase: requestPGPKeyPassphrase)
        }
        let original = legacyStore()
        guard let entity = original.fetchPasswordEntity(with: identifier) else {
            throw AppError.passwordFileNotFound(path: identifier)
        }
        return try decrypt(entity, in: original, keyID: keyID, requestPGPKeyPassphrase: requestPGPKeyPassphrase)
    }

    private func decrypt(_ entity: PasswordEntity, in store: PasswordStore, keyID: String?, requestPGPKeyPassphrase: @escaping (String) -> String) throws -> Password {
        if Defaults.isEnableGPGIDOn {
            return try store.decrypt(passwordEntity: entity, keyID: keyID, requestPGPKeyPassphrase: requestPGPKeyPassphrase)
        }
        return try store.decrypt(passwordEntity: entity, requestPGPKeyPassphrase: requestPGPKeyPassphrase)
    }

    /// Registers a new mount.
    public func add(_ config: PasswordStoreConfig) throws {
        try registry.add(config)
    }

    /// Removes a mount: its checkout, its entries, its cached store and its
    /// configuration. Other stores are untouched.
    public func remove(_ config: PasswordStoreConfig) {
        store(for: config).eraseStoreData()
        forget(configID: config.id)
        registry.remove(withID: config.id)
    }

    /// Clones a mount's remote into its own checkout. The store is only kept if
    /// the clone turns out to be a password store — a repository without a
    /// .gpg-id is not one, and leaving it configured would give the user a
    /// mount that can never decrypt anything.
    public func clone(
        _ config: PasswordStoreConfig,
        passwordProvider: @escaping GitCredential.PasswordProvider,
        transferProgressBlock: @escaping TransferProgressHandler = { _, _ in },
        checkoutProgressBlock: @escaping CheckoutProgressHandler = { _, _, _ in }
    ) throws {
        let store = store(for: config)
        let credential = GitCredential.from(
            authenticationMethod: config.authenticationMethod,
            userName: config.username,
            keyStore: AppKeychain.shared,
            keyStoreKey: config.authenticationMethod == .password ? config.gitPasswordKey : config.gitSSHPrivateKeyPassphraseKey
        )
        do {
            try store.cloneRepository(
                remoteRepoURL: config.gitURL,
                branchName: config.branchName,
                options: credential.getCredentialOptions(passwordProvider: passwordProvider),
                transferProgressBlock: transferProgressBlock,
                checkoutProgressBlock: checkoutProgressBlock
            )
        } catch {
            store.eraseStoreData()
            forget(configID: config.id)
            throw error
        }
        guard FileManager.default.fileExists(atPath: store.storeURL.appendingPathComponent(".gpg-id").path) else {
            store.eraseStoreData()
            forget(configID: config.id)
            throw AppError.other(message: "NoProperPassRepo.")
        }
    }

    /// The git credential for a store: the configured mount's own settings, or
    /// the app-wide ones for the original store.
    public func credential(forStore store: PasswordStore) -> GitCredential {
        guard
            store.storeID != PasswordStoreConfig.legacyStoreID,
            let uuid = UUID(uuidString: store.storeID),
            let config = registry.config(withID: uuid)
        else {
            return GitCredential.from(
                authenticationMethod: Defaults.gitAuthenticationMethod,
                userName: Defaults.gitUsername,
                keyStore: AppKeychain.shared
            )
        }
        return GitCredential.from(
            authenticationMethod: config.authenticationMethod,
            userName: config.username,
            keyStore: AppKeychain.shared,
            keyStoreKey: config.authenticationMethod == .password ? config.gitPasswordKey : config.gitSSHPrivateKeyPassphraseKey
        )
    }

    /// Drops a cached store, so the next request reopens its repository. Used
    /// after a mount is removed or re-cloned.
    public func forget(configID: UUID) {
        cache[configID.uuidString] = nil
    }
}
