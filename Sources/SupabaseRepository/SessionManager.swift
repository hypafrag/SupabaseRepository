//
//  SessionManager.swift
//
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
import Combine
import CommonUtils
import Supabase

public enum SessionError: LocalizedError {
    case notAuthorized
    case invalidCode
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "You're not authorized"
        case .invalidCode: return "The code is invalid"
        }
    }
}

public struct Session: Codable, Sendable {
    public let userId: UUID
    public let login: String
    
    public init(userId: UUID, login: String) {
        self.userId = userId
        self.login = login
    }
}

public struct Verification: Hashable, Sendable {
    let id: String
    public let login: String
    
    public init(id: String, login: String) {
        self.id = id
        self.login = login
    }
}

public protocol SessionManagerProtocol: Sendable {
    associatedtype SessionAPI: SessionAPIProtocol
    
    var session: ObservedValue<Session?> { get }
    var sessionAPI: SessionAPI { get }
    
    func verify(_ verification: Verification, code: String) async throws
    func activeSession() throws -> Session
    func signIn(phone: String) async throws -> Verification
    func logout() async throws
}

public extension SessionManagerProtocol {
    
    func setupSessionObserver() -> AnyCancellable {
        sessionAPI.didLogout.sink {
            if session() != nil {
                session.wrappedValue = nil
            }
        }
    }
    
    func verify(_ verification: Verification, code: String) async throws {
        do {
            let id = try await sessionAPI.signIn(verificationId: verification.id, code: code)
            session.wrappedValue = Session(userId: id, login: verification.login)
        } catch {
            /*if (error as NSError).code == 17044 { // check invalid code
                throw Error.invalidCode
            }*/
            throw error
        }
    }
    
    func activeSession() throws -> Session {
        if let session = session() {
            return session
        } else { throw SessionError.notAuthorized }
    }
    
    var isLoggedIn: Bool { session() != nil }
    
    func signIn(phone: String) async throws -> Verification {
        Verification(id: try await sessionAPI.verificationId(phoneNumber: phone), login: phone)
    }
    
    func signInWIthoutVerification(phone: String, password: String = "123456") async throws {
        do {
            let id = try await sessionAPI.signIn(phone: phone, password: password)
            session.wrappedValue = Session(userId: id, login: phone)
        } catch {
            if let error = error as? AuthError, error.errorCode == .invalidCredentials {
                let id = try await sessionAPI.signUp(phone: phone, password: password)
                session.wrappedValue = Session(userId: id, login: phone)
                return
            }
            throw error
        }
    }
    
    func logout() async throws {
        try await sessionAPI.logout()
    }
}
