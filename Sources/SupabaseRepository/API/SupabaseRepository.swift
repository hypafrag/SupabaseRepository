//
//  SupabaseRepository.swift
//
//
//  Created by Ilya Kuznetsov on 02/06/2024.
//

import Foundation
import Supabase
@_exported import CommonUtils
import UIKit
@_exported import Kingfisher

public struct SupabaseId: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ImageExtension: String {
    case jpg
    case png
}

public enum RemoteFile: Codable, Hashable, Sendable {
    case url(URL)
    case storage(BucketFilePath)
    
    public var fileURL: URL? {
        if case .url(let url) = self, url.isFileURL {
            return url
        }
        return nil
    }
}

public struct BucketFilePath: Codable, Hashable, Sendable {
    public let bucket: SupabaseId
    public let fileName: String
    
    public var key: String { "\(bucket.rawValue)/\(fileName)" }
    
    public init(bucket: SupabaseId, fileName: String) {
        self.bucket = bucket
        self.fileName = fileName
    }
    
    public init?(key: String) {
        let componetns = key.components(separatedBy: "/")
        
        if componetns.count >= 2 {
            self.bucket = SupabaseId(rawValue: componetns[0])
            self.fileName = componetns.dropFirst().joined(separator: "/")
        } else {
            return nil
        }
    }
}

public protocol SupabaseRepositoryProtocol: Sendable {
    
    var client: SupabaseClient { get }
    
    func imageProvider(path: ImageProviderPath) -> any ImageProviderProtocol
    
    func signedUrl(path: BucketFilePath) async throws -> URL
    func object(id: UUID, table: SupabaseId, select: String) async throws -> [String:Any]?
    func updateObject(id: UUID, table: SupabaseId, data: [String:Any]) async throws -> [String:Any]
    func upsertObject(id: UUID, table: SupabaseId, data: [String:Any]) async throws -> [String:Any]
    func deleteObject(id: UUID, table: SupabaseId) async throws
    func createObject(table: SupabaseId, data: [String:Any]) async throws -> [String:Any]
    func createObjects(table: SupabaseId, data: [[String:Any]]) async throws -> [[String:Any]]
    func customRequest<Body: Encodable>(path: String,
                                        method: String,
                                        body: Body,
                                        token: String?,
                                        apiKey: String,
                                        baseURL: URL) async throws -> [String : Any]
    func upload(file: URL, messageId: UUID, bucket: SupabaseId, suffix: String, contentType: String) async throws -> BucketFilePath
    func upload(image: URL, messageId: UUID, bucket: SupabaseId, suffix: String) async throws -> BucketFilePath
    func upload(image: UIImage, path: BucketFilePath, imageExtension: ImageExtension) async throws -> BucketFilePath
    func deleteImage(_ path: BucketFilePath) async
}

public extension PostgrestError {
    
    var isNotFound: Bool { code == "PGRST116" }
}

public extension SupabaseRepositoryProtocol {
    
    func signedUrl(path: BucketFilePath) async throws -> URL {
        try await client.storage.from(path.bucket.rawValue).createSignedURL(path: path.fileName, expiresIn: 60)
    }
    
    func object(id: UUID, table: SupabaseId, select: String = "*") async throws -> [String:Any]? {
        do {
            let result: AnyJSON = try await client.from(table.rawValue).select(select).match(["id" : id]).single().execute().value
            return try result.firstDictionary()
        } catch {
            if let error = error as? PostgrestError, error.isNotFound {
                return nil
            }
            throw error
        }
    }
    
    func updateObject(id: UUID, table: SupabaseId, data: [String:Any]) async throws -> [String:Any] {
        let result: AnyJSON = try await client.from(table.rawValue).update(data.jsonDictionary, returning: .representation).eq("id", value: id).execute().value
        return try result.firstDictionary()
    }
    
    func upsertObject(id: UUID, table: SupabaseId, data: [String:Any]) async throws -> [String:Any] {
        var resultData = data
        resultData["id"] = id.uuidString
        let result: AnyJSON = try await client.from(table.rawValue).upsert(resultData.jsonDictionary, returning: .representation).execute().value
        return try result.firstDictionary()
    }
    
    func deleteObject(id: UUID, table: SupabaseId) async throws {
        try await client.from(table.rawValue).delete().eq("id", value: id).execute()
    }
    
    func createObject(table: SupabaseId, data: [String:Any]) async throws -> [String:Any] {
        let result: AnyJSON = try await client.from(table.rawValue).insert(data.jsonDictionary, returning: .representation).execute().value
        return try result.firstDictionary()
    }
    
    func createObjects(table: SupabaseId, data: [[String:Any]]) async throws -> [[String:Any]] {
        let result: [AnyJSON] = try await client.from(table.rawValue).insert(data.jsonArray, returning: .representation).execute().value
        return result.anyArrayOfDict
    }
    
    func customRequest<Body: Encodable>(path: String, 
                                        method: String = "POST",
                                        body: Body,
                                        token: String? = nil,
                                        apiKey: String,
                                        baseURL: URL) async throws -> [String : Any] {
        var request = URLRequest(url: URL(string: baseURL.absoluteString + path)!)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        if let token = token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try body.toData()
        
        let result = try await URLSession.shared.data(for: request)
        let json = try AnyJSON.decode(result.0).firstDictionary()
        return json
    }
    
    func upload(file: URL, messageId: UUID, bucket: SupabaseId, suffix: String = "", contentType: String) async throws -> BucketFilePath {
        let data = try Data(contentsOf: file)
        let name = messageId.uuidString + suffix + ".\(file.pathExtension)"
        
        _ = try await client.storage.from(bucket.rawValue)
            .upload(name, data: data, options: .init(contentType: contentType, upsert: true))
        
        return .init(bucket: bucket, fileName: name)
    }
    
    func upload(image: URL, messageId: UUID, bucket: SupabaseId, suffix: String = "") async throws -> BucketFilePath {
        let result = try await upload(file: image, messageId: messageId, bucket: bucket, suffix: suffix, contentType: "image/\(image.pathExtension.lowercased())")
        
        if let data = try? Data(contentsOf: image), let resultImage = UIImage(data: data) {
            ImageCache.default.store(resultImage, forKey: result.key)
        }
        return result
    }
    
    func upload(image: UIImage, path: BucketFilePath, imageExtension: ImageExtension = .jpg) async throws -> BucketFilePath {
        let data: Data?
        
        switch imageExtension {
        case .jpg: data = image.jpegData(compressionQuality: 0.9)
        case .png: data = image.pngData()
        }
        
        guard let data else { throw RunError.custom("Cannot upload image") }
        
        _ = try await client.storage.from(path.bucket.rawValue)
            .upload(path.fileName, data: data, options: .init(contentType: "image/\(imageExtension.rawValue)", upsert: true))
        
        ImageCache.default.store(image, forKey: path.key)
        return path
    }
    
    func deleteImage(_ path: BucketFilePath) async {
        _ = try? await client.storage.from(path.bucket.rawValue).remove(paths: [path.fileName])
        ImageCache.default.removeImage(forKey: path.key)
    }
}
