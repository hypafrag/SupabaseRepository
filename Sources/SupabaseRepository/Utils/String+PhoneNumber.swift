//
//  String+PhoneNumber.swift
//

import Foundation
@_exported import PhoneNumberKit
@_exported import SwiftUIComponents

public extension String {
    
    fileprivate static let numberKit = PhoneNumberKit()
    fileprivate static let phoneFormatter = PartialFormatter(phoneNumberKit: numberKit)
    
    struct PhoneNumberFormatStyle: ParseableFormatStyle {
        
        public var parseStrategy: PhoneNumberParseStrategy { PhoneNumberParseStrategy() }
     
        public func format(_ value: String) -> String {
            if let result = try? parseStrategy.parse(value) {
                return result
            }
            return value
        }
    }
    
    func formatted(_ formatStyle: PhoneNumberFormatStyle) -> String {
        formatStyle.format(self)
    }
    
    static var defaultCountryCode: String? {
        if let code = numberKit.countryCode(for: phoneFormatter.defaultRegion) {
            return "\(code)"
        }
        return nil
    }
    
    var isValidPhone: ValidationResult {
        if !isValid || count < 3 {
            return .invalid()
        } else if !Self.numberKit.isValidPhoneNumber(self) {
            return .invalid("Invalid phone number")
        } else {
            return .valid
        }
    }
    
    var nonFormattedPhone: String {
        if let phone = try? Self.numberKit.parse(self) {
            let number = Self.numberKit.format(phone, toType: .international)
            return "+" + number.filter { $0.isNumber }
        } else {
            return "+" + filter { $0.isNumber }
        }
    }
}

public struct PhoneNumberParseStrategy: ParseStrategy {
     
    public func parse(_ value: String) throws -> String {
        let phone = value.components(separatedBy: "+")
            .last?.filter { $0.isNumber } ?? ""
        let nonFormatted = "+\(phone)"
        return String.phoneFormatter.formatPartial(nonFormatted)
    }
}

public extension FormatStyle where Self == String.PhoneNumberFormatStyle {
     
    static var phoneNumber: String.PhoneNumberFormatStyle {
        String.PhoneNumberFormatStyle()
    }
}
