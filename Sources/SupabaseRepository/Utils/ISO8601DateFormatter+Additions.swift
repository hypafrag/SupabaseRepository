//
//  ISO8601DateFormatter+Additions.swift
//

import Foundation

public extension String {
    
    var serviceDate: Date? {
        ISO8601DateFormatter.commonWithSeconds.date(from: self) ?? ISO8601DateFormatter.common.date(from: self)
    }
}

public extension Date {
    
    var serviceString: String { ISO8601DateFormatter.commonWithSeconds.string(from: self) }
}

public extension ISO8601DateFormatter {
    
    static let common: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    static let commonWithSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
