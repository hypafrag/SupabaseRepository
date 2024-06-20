//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
import Database
import CoreData
import UIKit
import Loader
import CommonUtils

public protocol UserRepository: AnyObject where User: NSManagedObject & Uploadable, User.Source == [String:Any], User.Id == UUID? {
    associatedtype User
    
    var database: Database { get }
    var userAPI: any UserAPIProtocol { get }
    var sessionManager: any SessionManagerProtocol { get }
    var currentUser: Loadable<User> { get }
    
    @MainActor func user(id: UUID) -> User?
    @MainActor func loadUser(id: UUID) async throws -> User?
    @MainActor func createUser(fill: @escaping (User)->()) async throws -> User
    @MainActor func editCurrentUser(_ update: @escaping (User)->()) async throws
    @MainActor func deleteAccount() async throws
    @discardableResult func updateCurrentUser() async throws -> User?
}

public protocol WithProfilePhoto: AnyObject {
    
    var profilePhoto: String? { get set }
}

public protocol UserRepositoryWithPhoto: UserRepository where User: WithProfilePhoto {
    
    @MainActor func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User
    @MainActor func editCurrentUser(newProfileImage: UIImage?, update: @escaping (User)->()) async throws
}

open class UserRepositoryWithPhotoImp<User: NSManagedObject & Uploadable & WithProfilePhoto>: UserRepositoryImp<User>, UserRepositoryWithPhoto where User.Id == UUID?, User.Source == [String:Any] {
    
    @MainActor public func createUser(fill: @escaping (User)->(), profileImage: UIImage?) async throws -> User {
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
    
    @MainActor public func editCurrentUser(newProfileImage: UIImage?, update: @escaping (User)->()) async throws {
        guard let user = currentUser.value else { throw SessionError.notAuthorized }
        
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

open class UserRepositoryImp<User: NSManagedObject & Uploadable>: UserRepository where User.Id == UUID?, User.Source == [String:Any] {
    
    open var userAPI: any UserAPIProtocol { fatalError("Should be overriden") }
    open var database: Database { fatalError("Should be overriden") }
    open var sessionManager: any SessionManagerProtocol { fatalError("Should be overriden") }
    open var currentUser: Loadable<User> { fatalError("Should be overriden") }
    
    public init() {
        sessionManager.sinkOnMain(retained: self) { [weak self] in
            guard let wSelf = self else { return }
            
            if wSelf.sessionManager.session == nil {
                wSelf.currentUser.cancelLoading()
                wSelf.currentUser.value = nil
            } else {
                Task { try await wSelf.updateCurrentUser() }
            }
        }
        
        if let userId = sessionManager.session?.userId {
            Task { @MainActor in
                currentUser.value = self.user(id: userId)
                try await self.updateCurrentUser()
            }
        }
    }
    
    @MainActor public func user(id: UUID) -> User? {
        User.findFirst(NSPredicate(format: "uid == %@", id.uuidString), ctx: database.viewContext)
    }
    
    @MainActor public func loadUser(id: UUID) async throws -> User? {
        if let data = try await userAPI.user(id: id) {
            return await database.edit {
                User.findAndUpdate(data, ctx: $0)?.getObjectId
            }?.object(database)
        }
        return nil
    }
    
    @MainActor public func createUser(fill: @escaping (User)->()) async throws -> User {
        let userId = try sessionManager.activeSession().userId
        
        let data = await database.fetch { ctx in
            var user = User(context: ctx)
            user.uid = userId
            fill(user)
            return user.toSource
        }
        
        let result = try await userAPI.createUser(data: data)
        
        let user = try await currentUser.load { [database] in
            await database.edit {
                User.findAndUpdate(result, ctx: $0)?.getObjectId
            }?.object(database)
        }
    
        guard let user else { throw RunError.custom("Cannot Create User") }
        
        return user
    }
    
    @MainActor public func editCurrentUser(_ update: @escaping (User)->()) async throws {
        guard let user = currentUser.value else { throw SessionError.notAuthorized }
        
        let dict = try await database.fetch(user) { user, ctx in
            update(user)
            return user.toSource
        }
        
        try await userAPI.updateUser(id: user.uid!, data: dict)
        
        try await database.edit(user) { user, ctx in
            user.update(dict)
        }
    }
    
    @MainActor public func deleteAccount() async throws {
        try await userAPI.deleteUser(userId: try sessionManager.activeSession().userId)
        try? await sessionManager.logout()
    }
    
    @discardableResult
    public func updateCurrentUser() async throws -> User? {
        try await currentUser.load { [weak self] in
            guard let wSelf = self else { throw CancellationError() }
            return try await wSelf.loadUser(id: wSelf.sessionManager.activeSession().userId)
        }
    }
}
