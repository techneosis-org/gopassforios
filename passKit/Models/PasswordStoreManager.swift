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

    /// Drops a cached store, so the next request reopens its repository. Used
    /// after a mount is removed or re-cloned.
    public func forget(configID: UUID) {
        cache[configID.uuidString] = nil
    }
}
