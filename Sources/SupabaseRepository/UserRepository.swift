//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
@_exported import Database
import CoreData
import UIKit
@_exported import Loader
@_exported import CommonUtils
import Combine

public protocol UserRepository: Sendable {
    associatedtype User: NSManagedObject & Uploadable where User.Source == [String:Any], User.Id == UUID?
    
    var database: Database { get }
    var userAPI: any UserAPIProtocol { get }
    var sessionManager: any SessionManagerProtocol { get }
    var user: Loadable<User> { get }
    
    @MainActor func user(id: UUID) -> User?
    func loadUser(id: UUID) async throws -> User?
    @MainActor func createUser(fill: @escaping (User)->()) async throws -> User
    @MainActor func editCurrentUser(_ update: @escaping (User)->()) async throws
    @MainActor func deleteAccount() async throws
    
    @discardableResult
    func updateCurrentUser() async throws -> User?
}

public extension UserRepository {
    
    @MainActor
    func setupUserRepositoryObserver() -> AnyCancellable {
        if let userId = sessionManager.session()?.userId {
            user.value = user(id: userId)
        }
        
        let observer = sessionManager.session.publisher.sink {
            if $0 == nil {
                user.cancelLoading()
                user.value = nil
            } else {
                Task { try await updateCurrentUser() }
            }
        }
        return observer
    }
    
    @MainActor
    func user(id: UUID) -> User? {
        User.findFirst(NSPredicate(format: "uid == %@", id.uuidString), ctx: database.viewContext)
    }
    
    func loadUser(id: UUID) async throws -> User? {
        if let data = try await userAPI.user(id: id) {
            return await database.edit {
                User.findAndUpdate(data, ctx: $0)?.getObjectId
            }?.object(database)
        }
        return nil
    }
    
    @MainActor func createUser(fill: @escaping (User)->()) async throws -> User {
        let userId = try sessionManager.activeSession().userId
        
        let data = await database.fetch { ctx in
            var user = User(context: ctx)
            user.uid = userId
            fill(user)
            return user.toSource
        }
        
        let result = try await userAPI.createUser(data: data)
        
        let user = try await user.load { [database] in
            await database.edit {
                User.findAndUpdate(result, ctx: $0)?.getObjectId
            }?.object(database)
        }
    
        guard let user else { throw RunError.custom("Cannot Create User") }
        
        return user
    }
    
    @MainActor func editCurrentUser(_ update: @escaping (User)->()) async throws {
        guard let user = user.value else { throw SessionError.notAuthorized }
        
        let dict = try await database.fetch(user) { user, ctx in
            update(user)
            return user.toSource
        }
        
        let result = try await userAPI.updateUser(id: user.uid!, data: dict)
        try await database.edit(user) { user, ctx in
            user.update(result)
        }
    }
    
    @MainActor func deleteAccount() async throws {
        try await userAPI.deleteUser(userId: try sessionManager.activeSession().userId)
        try? await sessionManager.logout()
    }
    
    func updateCurrentUser() async throws -> User? {
        try await user.load {
            try await loadUser(id: sessionManager.activeSession().userId)
        }
    }
}

public protocol WithProfilePhoto: AnyObject {
    
    var profilePhoto: String? { get set }
}

public protocol UserRepositoryWithPhoto: UserRepository where User: WithProfilePhoto {
    
    func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User
    func editCurrentUser(newProfileImage: UIImage?, update: @Sendable @escaping (User)->()) async throws
}

public extension UserRepositoryWithPhoto {
    
    func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User {
        let userId = try sessionManager.activeSession().userId
        
        var photoKey: String?
        if let image = profileImage {
            photoKey = try await userAPI.uploadProfile(image: image).key
        }
        
        return try await createUser {
            fill($0)
            $0.profilePhoto = photoKey
        }
    }
    
    func editCurrentUser(newProfileImage: UIImage?, update: @Sendable @escaping (User)->()) async throws {
        let photoKey = try await Task { @MainActor () -> String? in
            guard let user = user.value else { throw SessionError.notAuthorized }
            
            if let image = newProfileImage {
                if let profilePhoto = user.profilePhoto {
                    await userAPI.deleteProfileImage(key: profilePhoto)
                }
                return try await userAPI.uploadProfile(image: image).key
            } else {
                return user.profilePhoto
            }
        }.value
        
        try await editCurrentUser {
            update($0)
            $0.profilePhoto = photoKey
        }
    }
}
