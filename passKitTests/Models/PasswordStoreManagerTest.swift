//
//  PasswordStoreManagerTest.swift
//  passKitTests
//

import CoreData
import XCTest

@testable import passKit

final class PasswordStoreManagerTest: CoreDataTestCase {
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

    private var context: NSManagedObjectContext { controller.viewContext() }
    private var originalLegacyName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalLegacyName = Defaults.legacyStoreName
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
        Defaults.legacyStoreName = originalLegacyName
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

    // MARK: - qualified paths

    func testQualifiedPathCombinesMountAndPath() throws {
        let config = makeConfig(name: "work")
        try registry.add(config)
        let store = manager.store(for: config)
        let entity = PasswordEntity.insert(name: "bill.com", path: "bill.com.gpg", isDir: false, store: store.storeID, into: context)

        XCTAssertEqual(manager.qualifiedPath(for: entity), "work/bill.com.gpg")
    }

    func testQualifiedPathIsNilForAnUnconfiguredStore() {
        let entity = PasswordEntity.insert(name: "orphan", path: "orphan.gpg", isDir: false, store: UUID().uuidString, into: context)

        XCTAssertNil(manager.qualifiedPath(for: entity))
    }

    /// The same relative path in two mounts has to stay distinguishable —
    /// this is the whole reason paths are qualified.
    func testIdenticalPathsInDifferentStoresQualifyDifferently() throws {
        let personal = makeConfig(name: "personal")
        let work = makeConfig(name: "work")
        try registry.add(personal)
        try registry.add(work)

        let inPersonal = PasswordEntity.insert(name: "amazon", path: "amazon.gpg", isDir: false, store: manager.store(for: personal).storeID, into: context)
        let inWork = PasswordEntity.insert(name: "amazon", path: "amazon.gpg", isDir: false, store: manager.store(for: work).storeID, into: context)

        XCTAssertEqual(manager.qualifiedPath(for: inPersonal), "personal/amazon.gpg")
        XCTAssertEqual(manager.qualifiedPath(for: inWork), "work/amazon.gpg")
        XCTAssertNotEqual(manager.qualifiedPath(for: inPersonal), manager.qualifiedPath(for: inWork))
    }

    func testLegacyStoreIsNamedFromDefaults() {
        Defaults.legacyStoreName = "mine"

        XCTAssertEqual(manager.name(forStore: PasswordStoreConfig.legacyStoreID), "mine")
    }

    func testAllStoresLeadsWithTheOriginalStore() throws {
        try registry.add(makeConfig(name: "work"))

        XCTAssertEqual(manager.allStores.first?.storeID, legacyStub.storeID)
        XCTAssertEqual(manager.allStores.count, 2)
    }
}
