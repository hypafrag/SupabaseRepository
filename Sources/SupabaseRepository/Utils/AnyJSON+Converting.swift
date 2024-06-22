//
//  AnyJSON+Converting.swift
//

import Foundation
import Supabase
@_exported import CommonUtils

public extension AnyJSON {
    
    var anyValue: Any {
      switch self {
      case let .string(string): string
      case let .double(double): double
      case let .integer(integer): integer
      case let .object(dictionary): dictionary.anyDictionary
      case let .array(array): array.anyArray
      case let .bool(bool): bool
      case .null: NSNull()
      }
    }
    
    init(anyValue: Any) {
        self = switch anyValue {
        case let string as String: .string(string)
        case let integer as Int: .integer(integer)
        case let bool as Bool: .bool(bool)
        case let double as NSNumber: .double(double.doubleValue)
        case let dictionary as [String:Any]: .object(dictionary.jsonDictionary)
        case let array as [Any]: .array(array.jsonArray)
        case is NSNull: .null
        default: fatalError("Unsupported value: \(anyValue), please fix this")
        }
    }
    
    func firstDictionary() throws -> [String:Any] {
        if case .object(let dictionary) = self {
            return dictionary.anyDictionary
        } else if case .array(let array) = self, case .object(let dictionary) = array.first {
            return dictionary.anyDictionary
        }
        throw RunError.custom("Invalid Response")
    }
}

public extension [String:AnyJSON] {
    
    var anyDictionary: [String:Any] { reduce(into: [:]) { $0[$1.key] = $1.value.anyValue } }
}

public extension [AnyJSON] {
    
    var anyArray: [Any] { map { $0.anyValue } }
    
    var anyArrayOfDict: [[String:Any]] { compactMap { $0.anyValue as? [String:Any] } }
}

public extension [[String:Any]] {
    
    var jsonArray: [AnyJSON] { map { AnyJSON(anyValue: $0) } }
}

public extension [Any] {
    
    var jsonArray: [AnyJSON] { map { AnyJSON(anyValue: $0) } }
}

public extension [String:Any] {
    
    var jsonDictionary: [String:AnyJSON] {
        reduce(into: [:]) { $0[$1.key] = AnyJSON(anyValue: $1.value) }
    }
}
