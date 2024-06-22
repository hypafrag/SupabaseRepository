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
    
    public typealias Output = RemoteChange
    public typealias Failure = Never
    
    private let client: SupabaseClient
    private let table: SupabaseId
    private let filter: String
    private let withUpdates: Bool
    
    public init(client: SupabaseClient, table: SupabaseId, filter: String, withUpdates: Bool = true) {
        self.client = client
        self.table = table
        self.filter = filter
        self.withUpdates = withUpdates
    }
    
    private final class PublisherSubscription<S: Subscriber>: Subscription where S.Input == Output {
        
        @RWAtomic var channel: RealtimeChannelV2?
        @RWAtomic var tokens: [RealtimeChannelV2.Subscription] = []
        
        init(subscriber: S, client: SupabaseClient, table: SupabaseId, filter: String, withUpdates: Bool)  {
            Task {
                let channel = await client.realtimeV2.channel(table.rawValue)
                
                tokens.append(await channel.onPostgresChange(InsertAction.self, table: table.rawValue, filter: filter) { insert in
                    _ = subscriber.receive(.added(insert.record.anyDictionary))
                })
                
                tokens.append(await channel.onPostgresChange(DeleteAction.self, table: table.rawValue, filter: filter) { delete in
                    _ = subscriber.receive(.removed(delete.oldRecord.anyDictionary))
                })
                
                if withUpdates {
                    tokens.append(await channel.onPostgresChange(UpdateAction.self, table: table.rawValue, filter: filter) { update in
                        _ = subscriber.receive(.modified(update.record.anyDictionary))
                    })
                }
                self.channel = channel
                await channel.subscribe()
            }
        }
        
        func request(_ demand: Subscribers.Demand) { }

        func cancel() {
            tokens.forEach { $0.cancel() }
            tokens.removeAll()
        }
        
        deinit { 
            tokens.forEach { $0.cancel() }
            tokens.removeAll()
        }
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        subscriber.receive(subscription: PublisherSubscription<S>(subscriber: subscriber, client: client, table: table, filter: filter, withUpdates: withUpdates))
    }
}
