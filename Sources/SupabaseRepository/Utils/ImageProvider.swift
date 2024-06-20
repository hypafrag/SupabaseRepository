//
//  ImageProvider.swift
//

import Foundation
import Kingfisher
import DependencyContainer
import UIKit

public protocol ImageProviderProtocol: ImageDataProvider {
    
    var supabaseRepository: any SupabaseRepositoryProtocol { get }
    var path: ImageProviderPath { get }
}

public enum ImageProviderPath {
    case bucket(BucketFilePath)
    case url( URL)
    
    var key: String {
        switch self {
        case .bucket(let imagePath): imagePath.key
        case .url(let url): url.path
        }
    }
    
    func url(repository: any SupabaseRepositoryProtocol) async throws -> URL {
        switch self {
        case .bucket(let path): try await repository.signedUrl(path: path)
        case .url(let url): url
        }
    }
    
    public init?(_ key: String) {
        if let url = URL(string: key), url.scheme != nil {
            self = .url(url)
        } else if let path = BucketFilePath(key: key) {
            self = .bucket(path)
        } else {
            return nil
        }
    }
}

public extension ImageProviderProtocol {
    
    var cacheKey: String { path.key }
    
    func data(handler: @escaping (Result<Data, Swift.Error>) -> ()) {
        Task {
            do {
                let url = try await path.url(repository: supabaseRepository)
                _ = KingfisherManager.shared.downloader.downloadImage(with: url, options: []) {
                    switch $0 {
                    case .success(let result):
                        handler(.success(result.originalData))
                    case .failure(let error):
                        handler(.failure(error))
                    }
                }
            } catch {
                handler(.failure(error))
            }
        }
    }
    
    func image() async throws -> UIImage {
        let url = try await path.url(repository: supabaseRepository)
        return try await withCheckedThrowingContinuation { continuation in
            _ = KingfisherManager.shared.downloader.downloadImage(with: url, options: []) {
                switch $0 {
                case .success(let result):
                    continuation.resume(returning: result.image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
