//
//  SessionManager.swift
//
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation

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

public struct Session: Codable {
    public let userId: UUID
    let login: String
    
    public init(userId: UUID, login: String) {
        self.userId = userId
        self.login = login
    }
}

public struct Verification: Hashable {
    let id: String
    public let login: String
    
    public init(id: String, login: String) {
        self.id = id
        self.login = login
    }
}

public protocol SessionManagerProtocol: ObservableObject {
    
    var session: Session? { get set }
    
    var sessionAPI: any SessionAPIProtocol { get }
}

public extension SessionManagerProtocol {
    
    func setupLogout() {
        sessionAPI.didLogout.sinkMain(retained: self) { [weak self] in
            if let wSelf = self, wSelf.session != nil {
                wSelf.session = nil
            }
        }
    }
    
    func verify(_ verification: Verification, code: String) async throws {
        do {
            let id = try await sessionAPI.signIn(verificationId: verification.id, code: code)
            session = .init(userId: id, login: verification.login)
        } catch {
            /*if (error as NSError).code == 17044 { // check invalid code
                throw Error.invalidCode
            }*/
            throw error
        }
    }
    
    func activeSession() throws -> Session {
        if let session {
            return session
        } else { throw SessionError.notAuthorized }
    }
    
    var isLoggedIn: Bool { session != nil }
    
    func signIn(phone: String) async throws -> Verification {
        Verification(id: try await sessionAPI.verificationId(phoneNumber: phone), login: phone)
    }
    
    func logout() async throws {
        try await sessionAPI.logout()
    }
}
