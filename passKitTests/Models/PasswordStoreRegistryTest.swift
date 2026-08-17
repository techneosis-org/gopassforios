//
//  PasswordStoreRegistryTest.swift
//  passKitTests
//

import XCTest

@testable import passKit

final class PasswordStoreRegistryTest: XCTestCase {
    private var registry: PasswordStoreRegistry!

    private func makeConfig(name: String) -> PasswordStoreConfig {
        PasswordStoreConfig(name: name, gitURL: URL(string: "https://example.com/\(name).git")!)
    }

    override func setUp() {
        super.setUp()
        registry = PasswordStoreRegistry()
        registry.configs = []
    }

    override func tearDown() {
        registry.configs = []
        registry = nil
        super.tearDown()
    }

    func testAddedStoreIsPersisted() throws {
        let config = makeConfig(name: "personal")
        try registry.add(config)

        XCTAssertEqual(registry.configs.count, 1)
        XCTAssertEqual(registry.config(withID: config.id), config)
    }

    func testConfigsSurviveANewRegistryInstance() throws {
        try registry.add(makeConfig(name: "personal"))

        XCTAssertEqual(PasswordStoreRegistry().configs.map(\.name), ["personal"])
    }

    func testDuplicateNameIsRejected() throws {
        try registry.add(makeConfig(name: "personal"))

        XCTAssertThrowsError(try registry.add(makeConfig(name: "personal"))) { error in
            XCTAssertEqual(error as? AppError, .storeNameDuplicated)
        }
        XCTAssertEqual(registry.configs.count, 1)
    }

    func testDistinctNamesAreKeptInOrder() throws {
        try registry.add(makeConfig(name: "personal"))
        try registry.add(makeConfig(name: "work"))

        XCTAssertEqual(registry.configs.map(\.name), ["personal", "work"])
    }

    func testRemovingLeavesTheOtherStores() throws {
        let personal = makeConfig(name: "personal")
        try registry.add(personal)
        try registry.add(makeConfig(name: "work"))

        registry.remove(withID: personal.id)

        XCTAssertEqual(registry.configs.map(\.name), ["work"])
    }

    func testUpdateKeepsPositionAndDoesNotClashWithItself() throws {
        var personal = makeConfig(name: "personal")
        try registry.add(personal)
        try registry.add(makeConfig(name: "work"))

        personal.branchName = "trunk"
        try registry.update(personal)

        XCTAssertEqual(registry.configs.map(\.name), ["personal", "work"])
        XCTAssertEqual(registry.config(withID: personal.id)?.branchName, "trunk")
    }

    func testUpdateRejectsANameAnotherStoreHas() throws {
        var personal = makeConfig(name: "personal")
        try registry.add(personal)
        try registry.add(makeConfig(name: "work"))

        personal.name = "work"

        XCTAssertThrowsError(try registry.update(personal)) { error in
            XCTAssertEqual(error as? AppError, .storeNameDuplicated)
        }
        XCTAssertEqual(registry.config(withID: personal.id)?.name, "personal")
    }

    func testLocalURLIsStableAcrossRenames() throws {
        var config = makeConfig(name: "personal")
        let original = config.localURL

        config.name = "renamed"

        XCTAssertEqual(config.localURL, original)
    }
}
