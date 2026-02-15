//
//  CPTCode.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import Foundation
import SwiftData

struct CPTCode: Identifiable {
    let id: Int
    let code: String
    let description: String
    let rvu2020: Double
    let rvu2024: Double
}

@Model
final class DayRecord {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var countsData: Data

    init(date: Date, counts: [Int: Int]) {
        let normalizedDate = DayRecord.startOfDay(for: date)
        self.dayKey = DayRecord.key(for: normalizedDate)
        self.date = normalizedDate
        self.countsData = DayRecord.encode(counts)
    }

    var counts: [Int: Int] {
        get {
            DayRecord.decode(countsData)
        }
        set {
            countsData = DayRecord.encode(newValue)
        }
    }

    static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startOfDay(for: date))
    }

    private static func encode(_ counts: [Int: Int]) -> Data {
        let cleaned = counts
            .filter { $0.value > 0 }
            .reduce(into: [String: Int]()) { partialResult, item in
                partialResult[String(item.key)] = item.value
            }

        return (try? JSONEncoder().encode(cleaned)) ?? Data()
    }

    private static func decode(_ data: Data) -> [Int: Int] {
        guard
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }

        return decoded.reduce(into: [Int: Int]()) { partialResult, item in
            if let cptID = Int(item.key), item.value > 0 {
                partialResult[cptID] = item.value
            }
        }
    }
}

struct MonthlyRVUTotal: Identifiable {
    var id: Int { month }
    let month: Int
    let monthName: String
    let total2020: Double
    let total2024: Double
}

func rvuTotals(for counts: [Int: Int]) -> (total2020: Double, total2024: Double) {
    let cptByID = Dictionary(uniqueKeysWithValues: cptCodes.map { ($0.id, $0) })

    let total2020 = counts.reduce(0.0) { partialResult, item in
        guard let cpt = cptByID[item.key] else { return partialResult }
        return partialResult + (Double(item.value) * cpt.rvu2020)
    }

    let total2024 = counts.reduce(0.0) { partialResult, item in
        guard let cpt = cptByID[item.key] else { return partialResult }
        return partialResult + (Double(item.value) * cpt.rvu2024)
    }

    return (total2020, total2024)
}

func monthTotals(records: [DayRecord], containing date: Date) -> (monthLabel: String, total2020: Double, total2024: Double) {
    let calendar = Calendar.current
    guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
        return ("", 0, 0)
    }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateFormat = "LLLL yyyy"

    let monthAggregate = records
        .filter { monthInterval.contains($0.date) }
        .reduce((0.0, 0.0)) { partialResult, record in
            let dayTotals = rvuTotals(for: record.counts)
            return (partialResult.0 + dayTotals.total2020, partialResult.1 + dayTotals.total2024)
        }

    return (formatter.string(from: monthInterval.start), monthAggregate.0, monthAggregate.1)
}

func monthlyTotals(records: [DayRecord], year: Int) -> [MonthlyRVUTotal] {
    let calendar = Calendar.current

    return (1...12).map { month in
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let monthDate = calendar.date(from: components) ?? Date()
        let totalsForMonth = monthTotals(records: records, containing: monthDate)

        return MonthlyRVUTotal(
            month: month,
            monthName: calendar.monthSymbols[month - 1],
            total2020: totalsForMonth.total2020,
            total2024: totalsForMonth.total2024
        )
    }
}

let cptCodes = [
    CPTCode(id: 1, code: "99221", description: "Initial hospital care, level 1", rvu2020: 1.92, rvu2024: 1.63),
    CPTCode(id: 2, code: "99222", description: "Initial hospital care, level 2", rvu2020: 2.61, rvu2024: 2.60),
    CPTCode(id: 3, code: "99223", description: "Initial hospital care, level 3", rvu2020: 3.86, rvu2024: 3.50),
    CPTCode(id: 4, code: "99231", description: "Subsequent hospital care, level 1", rvu2020: 0.76, rvu2024: 1.00),
    CPTCode(id: 5, code: "99232", description: "Subsequent hospital care, level 2", rvu2020: 1.39, rvu2024: 1.59),
    CPTCode(id: 6, code: "99233", description: "Subsequent hospital care, level 3", rvu2020: 2.00, rvu2024: 2.40),
    CPTCode(id: 7, code: "99238", description: "Hospital discharge ≤30 min", rvu2020: 1.28, rvu2024: 1.50),
    CPTCode(id: 8, code: "99239", description: "Hospital discharge, >30 min", rvu2020: 1.90, rvu2024: 2.15),
    CPTCode(id: 9, code: "99291", description: "Critical care, first 30-74 min", rvu2020: 4.50, rvu2024: 4.50),
    CPTCode(id: 10, code: "99292", description: "Critical care, each add. 30 min", rvu2020: 2.25, rvu2024: 2.25),
    CPTCode(id: 11, code: "99406", description: "Smoking cessation, 3-10 min", rvu2020: 0.24, rvu2024: 0.24),
    CPTCode(id: 12, code: "99407", description: "Smoking cessation, >10 min", rvu2020: 0.50, rvu2024: 0.50),
    CPTCode(id: 13, code: "99497", description: "Advance care planning, 30 min", rvu2020: 3.86, rvu2024: 3.50),
    CPTCode(id: 14, code: "99498", description: "Advance care planning, add. 30 min", rvu2020: 1.40, rvu2024: 1.40),
    CPTCode(id: 15, code: "99356", description: "Prolonged inpatient service, 1 hr", rvu2020: 2.93, rvu2024: 2.93),
    CPTCode(id: 16, code: "99357", description: "Prolonged inpatient service, add. 30 min", rvu2020: 1.45, rvu2024: 1.45)
]
