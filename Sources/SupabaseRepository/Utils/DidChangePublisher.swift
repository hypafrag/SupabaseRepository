//
//  DidChangePublisher.swift
//

import Foundation
import Supabase
import Combine
@_exported import CommonUtils

public enum RemoteChange {
    case added([String:Any])
    case modified([String:Any])
    case removed([String:Any])
}

public struct DidChangePublisher: Publisher {
    
    public struct Changes: OptionSet {
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let added = Changes(rawValue: 1 << 0)
        public static let modified = Changes(rawValue: 1 << 1)
        public static let removed = Changes(rawValue: 1 << 2)
    }
    
    public typealias Output = RemoteChange
    public typealias Failure = Never
    
    private let client: SupabaseClient
    private let table: SupabaseId
    private let filter: String?
    private let changes: Changes
    
    public init(client: SupabaseClient, table: SupabaseId, filter: String?, changes: Changes = [.added, .modified, .removed]) {
        self.client = client
        self.table = table
        self.filter = filter
        self.changes = changes
    }
    
    private final class PublisherSubscription<S: Subscriber>: Subscription where S.Input == Output {
        
        let client: SupabaseClient
        let channel: RealtimeChannelV2
        @RWAtomic var tokens: [RealtimeChannelV2.Subscription] = []
        
        init(subscriber: S, client: SupabaseClient, table: SupabaseId, filter: String?, changes: Changes) {
            self.client = client
            self.channel = client.realtimeV2.channel(table.rawValue)
            
            Task {
                if changes.contains(.added) {
                    tokens.append(channel.onPostgresChange(InsertAction.self, table: table.rawValue, filter: filter) { insert in
                        _ = subscriber.receive(.added(insert.record.anyDictionary))
                    })
                }
                    
                if changes.contains(.removed) {
                    tokens.append(channel.onPostgresChange(DeleteAction.self, table: table.rawValue, filter: filter) { delete in
                        _ = subscriber.receive(.removed(delete.oldRecord.anyDictionary))
                    })
                }
                    
                if changes.contains(.modified) {
                    tokens.append(channel.onPostgresChange(UpdateAction.self, table: table.rawValue, filter: filter) { update in
                        _ = subscriber.receive(.modified(update.record.anyDictionary))
                    })
                }
                
                await channel.subscribe()
            }
        }
        
        func request(_ demand: Subscribers.Demand) { }

        func cancel() {
            tokens.forEach { $0.cancel() }
            tokens.removeAll()
            
            Task { [channel, client] in
                await channel.unsubscribe()
                await client.removeChannel(channel)
            }
        }
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        subscriber.receive(subscription: PublisherSubscription<S>(subscriber: subscriber, client: client, table: table, filter: filter, changes: changes))
    }
}
