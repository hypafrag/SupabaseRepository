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

public protocol UserRepository: AnyObject {
    associatedtype User: NSManagedObject & Uploadable where User.Source == [String:Any], User.Id == UUID?
    
    var database: Database { get }
    var userAPI: any UserAPIProtocol { get }
    var sessionManager: any SessionManagerProtocol { get }
    var user: Loadable<User> { get }
    
    @MainActor func user(id: UUID) -> User?
    @MainActor func loadUser(id: UUID) async throws -> User?
    @MainActor func createUser(fill: @escaping (User)->()) async throws -> User
    @MainActor func editCurrentUser(_ update: @escaping (User)->()) async throws
    @MainActor func deleteAccount() async throws
    func updateCurrentUser() async throws -> User?
}

public extension UserRepository {
    
    func setupUserRepository() {
        sessionManager.sinkOnMain(retained: self) { [weak self] in
            guard let wSelf = self else { return }
            
            if wSelf.sessionManager.session == nil {
                wSelf.user.cancelLoading()
                wSelf.user.value = nil
            } else {
                Task { try await wSelf.updateCurrentUser() }
            }
        }
        
        if let userId = sessionManager.session?.userId {
            Task { @MainActor in
                user.value = self.user(id: userId)
                _ = try await self.updateCurrentUser()
            }
        }
    }
    
    @MainActor func user(id: UUID) -> User? {
        User.findFirst(NSPredicate(format: "uid == %@", id.uuidString), ctx: database.viewContext)
    }
    
    @MainActor func loadUser(id: UUID) async throws -> User? {
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
        try await user.load { [weak self] in
            guard let wSelf = self else { throw CancellationError() }
            return try await wSelf.loadUser(id: wSelf.sessionManager.activeSession().userId)
        }
    }
}

public protocol WithProfilePhoto: AnyObject {
    
    var profilePhoto: String? { get set }
}

public protocol UserRepositoryWithPhoto: UserRepository where User: WithProfilePhoto {
    
    @MainActor func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User
    @MainActor func editCurrentUser(newProfileImage: UIImage?, update: @escaping (User)->()) async throws
}

public extension UserRepositoryWithPhoto {
    
    @MainActor func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User {
        let userId = try sessionManager.activeSession().userId
        
        var photoKey: String?
        if let image = profileImage {
            await userAPI.deleteProfileImage(userId: userId)
            photoKey = try await userAPI.uploadProfile(image: image, userId: userId).key
        }
        
        return try await createUser {
            fill($0)
            $0.profilePhoto = photoKey
        }
    }
    
    @MainActor func editCurrentUser(newProfileImage: UIImage?, update: @escaping (User)->()) async throws {
        guard let user = user.value else { throw SessionError.notAuthorized }
        
        var photoKey = user.profilePhoto
        if let image = newProfileImage {
            await userAPI.deleteProfileImage(userId: user.uid!)
            photoKey = try await userAPI.uploadProfile(image: image, userId: user.uid!).key
        }
        
        try await editCurrentUser {
            update($0)
            $0.profilePhoto = photoKey
        }
    }
}
