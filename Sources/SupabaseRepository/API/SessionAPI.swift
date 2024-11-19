//
//  SessionAPI.swift
//
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
@_exported import CommonUtils

public protocol SessionAPIProtocol: Sendable {
    var repository: any SupabaseRepositoryProtocol { get }
    var didLogout: VoidPublisher { get }
    
    func verificationId(phoneNumber: String) async throws -> String
    func signIn(verificationId: String, code: String) async throws -> UUID
    func logout() async throws
}

fileprivate var retainKey = 0

public extension SessionAPIProtocol {
    
    var didLogout: VoidPublisher {
        if let publisher = objc_getAssociatedObject(repository.client, &retainKey) as? VoidPublisher {
            return publisher
        } else {
            let publisher = VoidPublisher()
            objc_setAssociatedObject(repository.client, &retainKey, publisher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            Task { [weak client = repository.client] in
                if let auth = client?.auth {
                    for await state in auth.authStateChanges {
                        if state.event == .signedOut {
                            publisher.send()
                        }
                    }
                }
            }
            return publisher
        }
    }
    
    func verificationId(phoneNumber: String) async throws -> String {
        try await repository.client.auth.signInWithOTP(phone: phoneNumber)
        return phoneNumber
    }
    
    func signIn(verificationId: String, code: String) async throws -> UUID {
        try await repository.client.auth.verifyOTP(phone: verificationId, token: code, type: .sms).user.id
    }

    func signIn(phone: String, password: String) async throws -> UUID {
        try await repository.client.auth.signIn(phone: phone, password: password).user.id
    }

    func signUp(phone: String, password: String) async throws -> UUID {
        try await repository.client.auth.signUp(phone: phone, password: password).user.id
    }

    func logout() async throws {
        try await repository.client.auth.signOut()
    }
}
