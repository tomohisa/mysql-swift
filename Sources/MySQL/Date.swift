//
//  Date.swift
//  MySQL
//
//  Created by ito on 12/16/15.
//  Copyright © 2015 Yusuke Ito. All rights reserved.
//

import CoreFoundation
import Foundation
import SQLFormatter

internal final class SQLDateCalendar {
    fileprivate static let mutex = Mutex()
    
    private static var cals: [TimeZone:Calendar] = [:]
    
    internal static func calendar(forTimezone timeZone: TimeZone) -> Calendar {
        if let cal = cals[timeZone] {
            return cal
        }
        var newCal = Calendar(identifier: Calendar.Identifier.gregorian)
        newCal.timeZone = timeZone
        self.save(calendar: newCal, forTimeZone: timeZone)
        return newCal
    }
    
    private static func save(calendar cal: Calendar, forTimeZone timeZone: TimeZone) {
        cals[timeZone] = cal
    }
}

public struct SQLDate {
    
    public enum DateType {
        case date
        case dateTime
        case time
        case year
    }
    
    internal let timeInterval: TimeInterval?
    internal let sqlDate: String?
    internal let dateType: DateType
    
    public init(_ date: Date, dateType:DateType = .dateTime) {
        self.timeInterval = date.timeIntervalSince1970
        self.sqlDate = nil
        self.dateType = dateType
    }
    
    public init(_ timeIntervalSince1970: TimeInterval, dateType:DateType = .dateTime) {
        self.timeInterval = timeIntervalSince1970
        self.sqlDate = nil
        self.dateType = dateType
    }
    
    internal init(dateType:DateType = .dateTime) {
        self.init(Date(),dateType: dateType)
    }
    
    internal init(sqlDate: String, timeZone: TimeZone) throws {
        
        SQLDateCalendar.mutex.lock()
        
        defer {
            SQLDateCalendar.mutex.unlock()
        }
        self.sqlDate = sqlDate
        switch sqlDate.characters.count {
        case 4:
            if let year = Int(sqlDate) {
                var comp = DateComponents()
                comp.year = year
                comp.month = 1
                comp.day = 1
                comp.hour = 0
                comp.minute = 0
                comp.second = 0
                let cal = SQLDateCalendar.calendar(forTimezone: timeZone)
                if let date = cal.date(from: comp) {
                    self.dateType = .year
                    self.timeInterval = date.timeIntervalSince1970
                    return
                }
            }
        case 8:
            let chars:[Character] = Array(sqlDate.characters)
            if  let hour = Int(String(chars[0...1])),
                let minute = Int(String(chars[3...4])),
                let second = Int(String(chars[6...7])) {
                let year = 2000
                let month = 1
                let day = 1
                var comp = DateComponents()
                comp.year = year
                comp.month = month
                comp.day = day
                comp.hour = hour
                comp.minute = minute
                comp.second = second
                let cal = SQLDateCalendar.calendar(forTimezone: timeZone)
                if let date = cal.date(from :comp) {
                    self.dateType = .time
                    self.timeInterval = date.timeIntervalSince1970
                    return
                }
            }
        case 10:
            let chars:[Character] = Array(sqlDate.characters)
            self.dateType = .date
            if let year = Int(String(chars[0...3])),
                let month = Int(String(chars[5...6])),
                let day = Int(String(chars[8...9]))
                , year > 0 && day > 0 && month > 0 {
                let hour = 0
                let minute = 0
                let second = 0
                var comp = DateComponents()
                comp.year = year
                comp.month = month
                comp.day = day
                comp.hour = hour
                comp.minute = minute
                comp.second = second
                let cal = SQLDateCalendar.calendar(forTimezone: timeZone)
                if let date = cal.date(from :comp) {
                    self.timeInterval = date.timeIntervalSince1970
                    return
                }
            } else {
                self.timeInterval = nil
                return
            }
        case 19:
            let chars:[Character] = Array(sqlDate.characters)
            self.dateType = .dateTime
            if let year = Int(String(chars[0...3])),
                let month = Int(String(chars[5...6])),
                let day = Int(String(chars[8...9])),
                let hour = Int(String(chars[11...12])),
                let minute = Int(String(chars[14...15])),
                let second = Int(String(chars[17...18])) , year > 0 && day > 0 && month > 0 {
                var comp = DateComponents()
                comp.year = year
                comp.month = month
                comp.day = day
                comp.hour = hour
                comp.minute = minute
                comp.second = second
                let cal = SQLDateCalendar.calendar(forTimezone: timeZone)
                if let date = cal.date(from :comp) {
                    self.timeInterval = date.timeIntervalSince1970
                    return
                }
            } else {
                self.timeInterval = nil
                return
            }
        default: break
        }
        throw QueryError.invalidSQLDate(sqlDate)
    }
    
    fileprivate func pad(num: Int32!, digits: Int = 2) -> String {
        return pad(num: Int(num), digits: digits)
    }
    fileprivate func pad(num: Int8!, digits: Int = 2) -> String {
        return pad(num: Int(num), digits: digits)
    }
    
    fileprivate func pad(num: Int!, digits: Int = 2) -> String {
        let numUse = num ?? 0
        var str = String(numUse)
        if numUse < 0 {
            return str
        }
        while str.characters.count < digits {
            str = "0" + str
        }
        return str
    }
}

extension SQLDate: QueryParameter {
    public func queryParameter(option: QueryParameterOption) -> QueryParameterType {
        let compOptional = SQLDateCalendar.mutex.sync { () -> DateComponents? in
            let cal = SQLDateCalendar.calendar(forTimezone: option.timeZone)
            guard let date = date() else {
                return nil
            }
            return cal.dateComponents([ .year, .month,  .day,  .hour, .minute, .second], from: date)
        } // TODO: in Linux
        guard let comp = compOptional else {
            switch self.dateType {
            case .date:
                return "0000-00-00"
            case .time:
                return "00:00:00"
            case .year:
                return "0000"
            case .dateTime:
                return "0000-00-00 00:00:00"
            }
        }
        switch self.dateType {
        case .date:
            return QueryParameterWrap( "'\(pad(num: comp.year, digits: 4))-\(pad(num: comp.month))-\(pad(num: comp.day))'" )
        case .time:
            return QueryParameterWrap( "'\(pad(num: comp.hour)):\(pad(num: comp.minute)):\(pad(num: comp.second))'" )
        case .year:
            return QueryParameterWrap( "'\(pad(num: comp.year, digits: 4))'" )
        case .dateTime:
            return QueryParameterWrap( "'\(pad(num: comp.year, digits: 4))-\(pad(num: comp.month))-\(pad(num: comp.day)) \(pad(num: comp.hour)):\(pad(num: comp.minute)):\(pad(num: comp.second))'" )
        }
    }
}

extension SQLDate : CustomStringConvertible {
    public var description: String {
        guard let date = date() else {
            guard let sqlDate = self.sqlDate else {
                return ""
            }
            return sqlDate
        }
        return date.description
    }
}

extension SQLDate {
    public static func now(dateType:DateType = .dateTime) -> SQLDate {
        return SQLDate(dateType:dateType)
    }
    public func date() -> Date? {
        guard let timeInterval = self.timeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timeInterval)
    }
}

extension SQLDate: Equatable {
    
}

public func ==(lhs: SQLDate, rhs: SQLDate) -> Bool {
    return lhs.timeInterval == rhs.timeInterval
}

extension Date: QueryParameter {
    public func queryParameter(option: QueryParameterOption) throws -> QueryParameterType {
        return SQLDate(self).queryParameter(option: option)
    }
}
