//
//  PasswordEntity.swift
//  passKit
//
//  Created by Mingshen Sun on 11/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import CoreData
import DequeModule
import Foundation
import ObjectiveGit
import SwiftyUserDefaults

public final class PasswordEntity: NSManagedObject, Identifiable {
    /// Name of the password, i.e., filename without extension.
    @NSManaged public var name: String

    /// A Boolean value indicating whether the entity is a directory.
    @NSManaged public var isDir: Bool

    /// A Boolean value indicating whether the entity is synced with remote repository.
    @NSManaged public var isSynced: Bool

    /// The relative file path of the password or directory, within its store.
    @NSManaged public var path: String

    /// Identifier of the store this entry belongs to. `path` is only unique
    /// within a store, so anything resolving an entry to a file needs both.
    @NSManaged public var store: String

    /// The thumbnail image of the password if there is a url entry in the password.
    @NSManaged public var image: Data?

    /// The parent password entity.
    @NSManaged public var parent: PasswordEntity?

    /// A set of child password entities.
    @NSManaged public var children: Set<PasswordEntity>

    @nonobjc
    public static func fetchRequest() -> NSFetchRequest<PasswordEntity> {
        NSFetchRequest<PasswordEntity>(entityName: "PasswordEntity")
    }

    /// A String value with password directory and name, i.e., path without extension.
    public var nameWithDir: String {
        (path as NSString).deletingPathExtension
    }

    public var dirText: String {
        getDirArray().joined(separator: " > ")
    }

    public func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(path)
    }

    public func getDirArray() -> [String] {
        var parentEntity = parent
        var passwordCategoryArray: [String] = []
        while let current = parentEntity {
            passwordCategoryArray.append(current.name)
            parentEntity = current.parent
        }
        passwordCategoryArray.reverse()
        return passwordCategoryArray
    }

    public static func fetchAll(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func fetchAllPassword(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isDir = false")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func totalNumber(in context: NSManagedObjectContext) -> Int {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isDir = false")
        return (try? context.count(for: request)) ?? 0
    }

    public static func fetchUnsynced(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isSynced = false")
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func fetch(by path: String, store: String, in context: NSManagedObjectContext) -> PasswordEntity? {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "path = %@ and store = %@", path, store)
        return try? context.fetch(request).first as? Self
    }

    public static func fetch(by path: String, isDir: Bool, store: String, in context: NSManagedObjectContext) -> PasswordEntity? {
        let request = Self.fetchRequest()

        request.predicate = NSPredicate(format: "path = %@ and isDir = %@ and store = %@", path, isDir as NSNumber, store)
        return try? context.fetch(request).first as? Self
    }

    public static func fetch(by parent: PasswordEntity?, in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "parent = %@", parent ?? 0)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func updateAllToSynced(in context: NSManagedObjectContext) -> Int {
        let request = NSBatchUpdateRequest(entity: Self.entity())
        request.resultType = .updatedObjectsCountResultType
        request.predicate = NSPredicate(format: "isSynced = false")
        request.propertiesToUpdate = ["isSynced": true]
        let result = try? context.execute(request) as? NSBatchUpdateResult
        return result?.result as? Int ?? 0
    }

    public static func deleteRecursively(entity: PasswordEntity, in context: NSManagedObjectContext) {
        var currentEntity: PasswordEntity? = entity

        while let node = currentEntity, node.children.isEmpty {
            let parent = node.parent
            context.delete(node)
            try? context.save()
            currentEntity = parent
        }
    }

    public static func deleteAll(in context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: Self.fetchRequest())
        _ = try? context.execute(deleteRequest)
    }

    /// Removes only one store's entries, so erasing a mount leaves the others
    /// intact.
    public static func deleteAll(store: String, in context: NSManagedObjectContext) {
        // Spelled out rather than reusing fetchRequest(): a batch delete needs
        // the untyped request, and the typed overload wins inference here.
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "PasswordEntity")
        request.predicate = NSPredicate(format: "store = %@", store)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try? context.execute(deleteRequest)
    }

    public static func exists(password: Password, store: String, in context: NSManagedObjectContext) -> Bool {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "name = %@ and path = %@ and isDir = false and store = %@", password.name, password.path, store)
        if let count = try? context.count(for: request) {
            return count > 0
        }
        return false
    }

    @discardableResult
    public static func insert(name: String, path: String, isDir: Bool, store: String, into context: NSManagedObjectContext) -> PasswordEntity {
        let entity = PasswordEntity(context: context)
        entity.name = name
        entity.path = path
        entity.isDir = isDir
        entity.isSynced = false
        entity.store = store
        return entity
    }

    public static func initPasswordEntityCoreData(url: URL, store: String, mountName: String, in context: NSManagedObjectContext) {
        let localFileManager = FileManager.default
        let url = url.resolvingSymlinksInPath()

        // The root is kept rather than discarded, named after the mount, so
        // each store's contents hang beneath it. Without it every store's
        // top-level entries share a nil parent and are indistinguishable in
        // the list. Its own path stays empty, so paths under it remain
        // relative to the store and still resolve to files.
        let root = {
            let entity = PasswordEntity(context: context)
            entity.name = mountName
            entity.isDir = true
            entity.path = ""
            entity.store = store
            return entity
        }()
        // Directories are enumerated through their resolved URL, so that symbolically linked
        // directories are traversed as well. A link pointing back up the tree would make the
        // traversal loop forever, hence every directory also carries the resolved paths of
        // itself and all its ancestors.
        var queue: Deque = [(entity: root, url: url, ancestors: Set([url.path]))]
        while let (current, currentURL, ancestors) = queue.popFirst() {
            let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey])
            let options = FileManager.DirectoryEnumerationOptions([.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            guard let directoryEnumerator = localFileManager.enumerator(at: currentURL, includingPropertiesForKeys: Array(resourceKeys), options: options) else {
                continue
            }
            for case let fileURL as URL in directoryEnumerator {
                // Keep the name and the path of the link itself, since pass uses symbolic
                // links to share one password between several entries. Only the type comes
                // from the target, because isDirectoryKey does not follow links.
                let resolvedURL = fileURL.resolvingSymlinksInPath()
                guard let name = (try? fileURL.resourceValues(forKeys: resourceKeys))?.name else {
                    continue
                }
                let isDirectory = (try? resolvedURL.resourceValues(forKeys: resourceKeys))?.isDirectory ?? false
                // Ignore files that are not passwords, e.g., a README.md documenting the store.
                guard isDirectory || (name as NSString).pathExtension.lowercased() == "gpg" else {
                    continue
                }
                let passwordEntity = PasswordEntity(context: context)
                passwordEntity.isDir = isDirectory
                passwordEntity.store = store
                if isDirectory {
                    passwordEntity.name = name
                    if !ancestors.contains(resolvedURL.path) {
                        queue.append((passwordEntity, resolvedURL, ancestors.union([resolvedURL.path])))
                    }
                } else {
                    passwordEntity.name = (name as NSString).deletingPathExtension
                }
                passwordEntity.parent = current
                passwordEntity.path = current.path.isEmpty ? name : "\(current.path)/\(name)"
            }
        }
    }
}

public extension PasswordEntity {
    @objc(addChildrenObject:)
    @NSManaged
    func addToChildren(_ value: PasswordEntity)

    @objc(removeChildrenObject:)
    @NSManaged
    func removeFromChildren(_ value: PasswordEntity)

    @objc(addChildren:)
    @NSManaged
    func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged
    func removeFromChildren(_ values: NSSet)
}
