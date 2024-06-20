//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
import UIKit

public extension SupabaseId {
    static let usersTable = SupabaseId(rawValue: "users")
    static let avatarsBucket = SupabaseId(rawValue: "avatars")
}

public protocol UserAPIProtocol {
    var repository: SupabaseRepositoryProtocol { get }
    
    var userScope: String { get }
}

public extension UserAPIProtocol {
    
    var userScope: String { "*" }
    
    func user(id: UUID) async throws -> [String:Any]? {
        try await repository.object(id: id, table: .usersTable, select: userScope)
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
    
    func uploadProfile(image: UIImage, userId: UUID, imageExtension: ImageExtension = .jpg) async throws -> BucketFilePath {
        try await repository.upload(image: image.reduced(1024), path: BucketFilePath(bucket: .avatarsBucket, fileName: userId.uuidString + ".\(imageExtension.rawValue)"), imageExtension: imageExtension)
    }
    
    func deleteProfileImage(userId: UUID, imageExtension: ImageExtension = .jpg) async {
        await repository.deleteImage(BucketFilePath(bucket: .avatarsBucket, fileName: userId.uuidString + ".\(imageExtension.rawValue)"))
    }
}
