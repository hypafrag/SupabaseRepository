//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
import UIKit
import Supabase

public extension SupabaseId {
    static let usersTable = SupabaseId(rawValue: "users")
    static let avatarsBucket = SupabaseId(rawValue: "avatars")
}

public protocol UserAPIProtocol: Sendable {
    
    var repository: any SupabaseRepositoryProtocol { get }
    var userScope: String { get }
    
    func user(id: UUID) async throws -> [String:Any]?
    func users(ids: [UUID]) async throws -> [[String:Any]]
    func createUser(data: [String:Any]) async throws -> [String:Any]
    func updateUser(id: UUID, data: [String:Any]) async throws -> [String:Any]
    func deleteUser(userId: UUID) async throws
    @available (*, deprecated, message: "Use `uploadProfile(image:, imageExtension:)` instead")
    func uploadProfile(image: UIImage, userId: UUID, imageExtension: ImageExtension) async throws -> BucketFilePath
    func uploadProfile(image: UIImage, imageExtension: ImageExtension) async throws -> BucketFilePath
    @available (*, deprecated, message: "Use `deleteProfileImage(key:)` instead")
    func deleteProfileImage(userId: UUID, imageExtension: ImageExtension) async
    func deleteProfileImage(key: String) async
}

public extension UserAPIProtocol {
    
    var userScope: String { "*" }
    
    func user(id: UUID) async throws -> [String:Any]? {
        try await repository.object(id: id, table: .usersTable, select: userScope)
    }
    
    func users(ids: [UUID]) async throws -> [[String:Any]] {
        if ids.isEmpty { return [] }
        
        let result: [AnyJSON] = try await repository.client.from(SupabaseId.usersTable.rawValue)
            .select("*,latestStory:stories!latest_story_id(*)")
            .in("id", values: ids).execute().value
        return result.anyArrayOfDict
    }
    
    func createUser(data: [String:Any]) async throws -> [String:Any] {
        try await repository.createObject(table: .usersTable, data: data)
    }
    
    @discardableResult
    func updateUser(id: UUID, data: [String:Any]) async throws -> [String:Any] {
        try await repository.updateObject(id: id, table: .usersTable, data: data)
    }
    
    func deleteUser(userId: UUID) async throws {
        try await repository.deleteObject(id: userId, table: .usersTable)
    }
    
    @available (*, deprecated, message: "Use `uploadProfile(image:, imageExtension:)` instead")
    func uploadProfile(image: UIImage, userId: UUID, imageExtension: ImageExtension = .jpg) async throws -> BucketFilePath {
        try await repository.upload(image: image.reduced(1024), path: BucketFilePath(bucket: .avatarsBucket, fileName: userId.uuidString + ".\(imageExtension.rawValue)"), imageExtension: imageExtension)
    }
    
    func uploadProfile(image: UIImage, imageExtension: ImageExtension = .jpg) async throws -> BucketFilePath {
        try await repository.upload(image: image.reduced(1024), path: BucketFilePath(bucket: .avatarsBucket, fileName: UUID().uuidString + ".\(imageExtension.rawValue)"), imageExtension: imageExtension)
    }
    
    @available (*, deprecated, message: "Use `deleteProfileImage(key:)` instead")
    func deleteProfileImage(userId: UUID, imageExtension: ImageExtension = .jpg) async {
        await repository.deleteImage(BucketFilePath(bucket: .avatarsBucket, fileName: userId.uuidString + ".\(imageExtension.rawValue)"))
    }
    
    func deleteProfileImage(key: String) async {
        guard let path = BucketFilePath(key: key) else { return }
        await repository.deleteImage(path)
    }
}
