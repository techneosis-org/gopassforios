//
//  PasswordStoreManagerTest.swift
//  passKitTests
//

import XCTest

@testable import passKit

final class PasswordStoreManagerTest: XCTestCase {
    private var registry: PasswordStoreRegistry!
    private var manager: PasswordStoreManager!

    private func makeConfig(name: String) -> PasswordStoreConfig {
        PasswordStoreConfig(name: name, gitURL: URL(string: "https://example.com/\(name).git")!)
    }

    /// Stands in for the pre-multi-store singleton. Built with an ordinary
    /// identifier so that constructing it does not run the legacy key
    /// migration, which writes to the shared keychain and would disturb
    /// unrelated tests.
    private var legacyStub: PasswordStore!

    override func setUp() {
        super.setUp()
        registry = PasswordStoreRegistry()
        registry.configs = []
        let stub = PasswordStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("legacy-stub", isDirectory: true),
            storeID: "legacy-stub"
        )
        legacyStub = stub
        manager = PasswordStoreManager(registry: registry, legacyStore: stub)
    }

    override func tearDown() {
        registry.configs = []
        registry = nil
        manager = nil
        legacyStub = nil
        super.tearDown()
    }

    func testStoreIsCachedPerConfig() {
        let config = makeConfig(name: "personal")

        let first = manager.store(for: config)
        let second = manager.store(for: config)

        XCTAssertTrue(first === second)
    }

    func testStoresAreDistinctBetweenConfigs() {
        let personal = manager.store(for: makeConfig(name: "personal"))
        let work = manager.store(for: makeConfig(name: "work"))

        XCTAssertFalse(personal === work)
        XCTAssertNotEqual(personal.storeID, work.storeID)
        XCTAssertNotEqual(personal.storeURL, work.storeURL)
    }

    func testStoreUsesTheConfigsCheckoutAndIdentity() {
        let config = makeConfig(name: "personal")

        let store = manager.store(for: config)

        XCTAssertEqual(store.storeURL, config.localURL)
        XCTAssertEqual(store.storeID, config.id.uuidString)
    }

    func testStoresFollowsTheRegistryOrder() throws {
        try registry.add(makeConfig(name: "personal"))
        try registry.add(makeConfig(name: "work"))

        XCTAssertEqual(manager.stores.map(\.storeID), registry.configs.map(\.id.uuidString))
    }

    func testLookupByIdentifierFindsAConfiguredStore() throws {
        let config = makeConfig(name: "personal")
        try registry.add(config)

        XCTAssertEqual(manager.store(withID: config.id.uuidString)?.storeURL, config.localURL)
    }

    func testLookupByIdentifierIsNilForAnUnknownStore() {
        XCTAssertNil(manager.store(withID: UUID().uuidString))
        XCTAssertNil(manager.store(withID: "not-a-uuid"))
    }

    func testLegacyIdentifierResolvesToTheOriginalStore() {
        XCTAssertTrue(manager.store(withID: PasswordStoreConfig.legacyStoreID) === legacyStub)
    }

    func testForgettingDropsTheCachedStore() {
        let config = makeConfig(name: "personal")
        let first = manager.store(for: config)

        manager.forget(configID: config.id)

        XCTAssertFalse(manager.store(for: config) === first)
    }

    func testCredentialKeysAreScopedPerStore() {
        let personal = manager.store(for: makeConfig(name: "personal"))
        let work = manager.store(for: makeConfig(name: "work"))

        XCTAssertNotEqual(personal.gitPasswordKey, work.gitPasswordKey)
        XCTAssertNotEqual(personal.gitSSHPrivateKeyPassphraseKey, work.gitSSHPrivateKeyPassphraseKey)
    }

    /// The original store must keep writing to the unsuffixed keys, otherwise
    /// an upgrade would lose the git credentials already saved on the device.
    /// Asserted against the derivation rather than a constructed store, since
    /// building one with the legacy identifier runs the key migration.
    func testLegacyStoreKeepsTheOriginalCredentialKeys() {
        let legacy = PasswordStoreConfig.legacyStoreID

        XCTAssertEqual(PasswordStore.gitPasswordKey(forStore: legacy), Globals.gitPassword)
        XCTAssertEqual(PasswordStore.gitSSHPrivateKeyPassphraseKey(forStore: legacy), Globals.gitSSHPrivateKeyPassphrase)
    }
}
