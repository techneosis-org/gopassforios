//
//  PasswordStoreRegistry.swift
//  passKit
//

import Foundation
import SwiftyUserDefaults

/// The set of stores the app has been told about.
///
/// This only owns the configuration. Cloning a store, reading it, and keeping
/// its entries in the database remain the job of `PasswordStore`; the registry
/// decides which stores exist and hands out their descriptions.
public final class PasswordStoreRegistry {
    public static let shared = PasswordStoreRegistry()

    public init() {}

    public var configs: [PasswordStoreConfig] {
        get { Defaults.passwordStores }
        set { Defaults.passwordStores = newValue }
    }

    public func config(withID id: UUID) -> PasswordStoreConfig? {
        configs.first { $0.id == id }
    }

    /// Mount names have to stay distinct: they are how a store is identified in
    /// the interface, and eventually how its subtree is labelled, so two stores
    /// sharing one would be indistinguishable.
    public func add(_ config: PasswordStoreConfig) throws {
        guard !configs.contains(where: { $0.name == config.name }) else {
            throw AppError.storeNameDuplicated
        }
        configs.append(config)
    }

    public func remove(withID id: UUID) {
        configs.removeAll { $0.id == id }
    }

    /// Replaces a stored configuration, keeping its position in the list. The
    /// name check excludes the store being updated so that editing anything
    /// else about it does not trip over its own name.
    public func update(_ config: PasswordStoreConfig) throws {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else {
            return
        }
        guard !configs.contains(where: { $0.name == config.name && $0.id != config.id }) else {
            throw AppError.storeNameDuplicated
        }
        configs[index] = config
    }
}
