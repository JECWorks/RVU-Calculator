//
//  CPTCode.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import Foundation
import SwiftData

// Groups the CPT/HCPCS catalog into clinician-facing charge-entry profiles.
// The raw value is stored in AppStorage, so keep these case names stable.
enum ProviderProfile: String, CaseIterable, Identifiable {
    case hospitalist
    case criticalCare
    case emergencyMedicine
    case pediatricHospitalist
    case pediatricCriticalCare
    case neonatology
    case snfPostAcute
    case consultPayerDependent

    var id: String { rawValue }

    // Human-readable label used in the profile picker.
    var displayName: String {
        switch self {
        case .hospitalist: "Hospitalist"
        case .criticalCare: "Critical Care"
        case .emergencyMedicine: "Emergency Medicine"
        case .pediatricHospitalist: "Pediatric Hospitalist"
        case .pediatricCriticalCare: "Pediatric Critical Care"
        case .neonatology: "Neonatology"
        case .snfPostAcute: "SNF / Post-Acute"
        case .consultPayerDependent: "Consult / Payer-Dependent"
        }
    }
}

// Controls whether the UI shows one RVU schedule or compares two schedules.
// The raw value is stored in AppStorage, so keep these case names stable.
enum RVUScheduleMode: String, CaseIterable, Identifiable {
    case single
    case compare

    var id: String { rawValue }

    // Label used in the schedule mode segmented control.
    var displayName: String {
        switch self {
        case .single: "Single Year"
        case .compare: "Compare Years"
        }
    }
}

// The curated schedule years available in the app's static RVU catalog.
let supportedRVUYears = [2020, 2024, 2026]

// Describes one billable CPT/HCPCS row in the curated catalog.
// IDs are persisted in DayRecord.countsData, so existing ids should not be reused.
struct CPTCode: Identifiable {
    let id: Int
    let code: String
    let description: String
    let profiles: Set<ProviderProfile>
    let rvusByYear: [Int: Double]
    let warning: String?

    // The initializer keeps warning optional so most catalog rows stay compact.
    init(
        id: Int,
        code: String,
        description: String,
        profiles: Set<ProviderProfile>,
        rvusByYear: [Int: Double],
        warning: String? = nil
    ) {
        self.id = id
        self.code = code
        self.description = description
        self.profiles = profiles
        self.rvusByYear = rvusByYear
        self.warning = warning
    }

    // Returns nil when a code was not priced in the selected schedule year.
    // The UI displays those missing per-code values as N/A and excludes them from totals.
    func rvu(for year: Int) -> Double? {
        rvusByYear[year]
    }
}

// One saved day of charge counts. The model stores CPT ids and counts as JSON
// so the SwiftData schema can stay stable as the static catalog expands.
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

    // Decoded view of countsData. Keys are CPTCode.id values, not CPT code strings.
    var counts: [Int: Int] {
        get {
            DayRecord.decode(countsData)
        }
        set {
            countsData = DayRecord.encode(newValue)
        }
    }

    // ## Normalizes a timestamp to local calendar day boundaries for storage consistency.
    static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // ## Builds a stable yyyy-MM-dd key used for unique day record lookup.
    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startOfDay(for: date))
    }

    // ## Serializes positive CPT counts to JSON data for persistence.
    private static func encode(_ counts: [Int: Int]) -> Data {
        let cleaned = counts
            .filter { $0.value > 0 }
            .reduce(into: [String: Int]()) { partialResult, item in
                partialResult[String(item.key)] = item.value
            }

        return (try? JSONEncoder().encode(cleaned)) ?? Data()
    }

    // ## Deserializes persisted CPT counts and filters invalid/zero entries.
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

// Month summary row used by the yearly totals screen.
struct MonthlyRVUTotal: Identifiable {
    var id: Int { month }
    let month: Int
    let monthName: String
    let totalsByYear: [Int: Double]
}

// ## Computes aggregate RVU totals from CPT counts for the selected fee schedule years.
func rvuTotals(for counts: [Int: Int], years: [Int]) -> [Int: Double] {
    let cptByID = Dictionary(uniqueKeysWithValues: cptCodes.map { ($0.id, $0) })

    return years.reduce(into: [Int: Double]()) { partialResult, year in
        partialResult[year] = counts.reduce(0.0) { runningTotal, item in
            guard let cpt = cptByID[item.key], let rvu = cpt.rvu(for: year) else {
                return runningTotal
            }
            return runningTotal + (Double(item.value) * rvu)
        }
    }
}

// ## Computes monthly RVU totals for the month containing the provided date.
func monthTotals(records: [DayRecord], containing date: Date, years: [Int]) -> (monthLabel: String, totalsByYear: [Int: Double]) {
    let calendar = Calendar.current
    guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
        return ("", Dictionary(uniqueKeysWithValues: years.map { ($0, 0.0) }))
    }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateFormat = "LLLL yyyy"

    let monthAggregate = records
        .filter { monthInterval.contains($0.date) }
        .reduce(into: Dictionary(uniqueKeysWithValues: years.map { ($0, 0.0) })) { partialResult, record in
            let dayTotals = rvuTotals(for: record.counts, years: years)
            for year in years {
                partialResult[year, default: 0] += dayTotals[year, default: 0]
            }
        }

    return (formatter.string(from: monthInterval.start), monthAggregate)
}

// ## Produces month-by-month RVU totals for the selected calendar year.
func monthlyTotals(records: [DayRecord], year: Int, scheduleYears: [Int]) -> [MonthlyRVUTotal] {
    let calendar = Calendar.current

    return (1...12).map { month in
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let monthDate = calendar.date(from: components) ?? Date()
        let totalsForMonth = monthTotals(records: records, containing: monthDate, years: scheduleYears)

        return MonthlyRVUTotal(
            month: month,
            monthName: calendar.monthSymbols[month - 1],
            totalsByYear: totalsForMonth.totalsByYear
        )
    }
}

// Warnings are intentionally centralized so repeated catalog rows share exact wording.
private let consultWarning = "Inpatient consult codes may not be recognized by some payors; consider changing to initial visit codes instead."
private let legacyProlongedWarning = "Legacy prolonged inpatient codes are retained for older saved entries; Medicare now generally uses G0316 for inpatient or observation prolonged E/M."

// Static curated catalog. Work RVUs are from CMS PFS Relative Value Files for
// 2020, 2024, and 2026. Append new rows with new ids; do not renumber old rows.
let cptCodes = [
    CPTCode(id: 1, code: "99221", description: "Initial hospital or observation care, level 1", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 1.92, 2024: 1.63, 2026: 1.63]),
    CPTCode(id: 2, code: "99222", description: "Initial hospital or observation care, level 2", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 2.61, 2024: 2.60, 2026: 2.60]),
    CPTCode(id: 3, code: "99223", description: "Initial hospital or observation care, level 3", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 3.86, 2024: 3.50, 2026: 3.50]),
    CPTCode(id: 4, code: "99231", description: "Subsequent hospital or observation care, level 1", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 0.76, 2024: 1.00, 2026: 1.00]),
    CPTCode(id: 5, code: "99232", description: "Subsequent hospital or observation care, level 2", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 1.39, 2024: 1.59, 2026: 1.59]),
    CPTCode(id: 6, code: "99233", description: "Subsequent hospital or observation care, level 3", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 2.00, 2024: 2.40, 2026: 2.40]),
    CPTCode(id: 7, code: "99238", description: "Hospital discharge, 30 minutes or less", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 1.28, 2024: 1.50, 2026: 1.50]),
    CPTCode(id: 8, code: "99239", description: "Hospital discharge, more than 30 minutes", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 1.90, 2024: 2.15, 2026: 2.15]),
    CPTCode(id: 9, code: "99291", description: "Critical care, first 30-74 minutes", profiles: [.criticalCare], rvusByYear: [2020: 4.50, 2024: 4.50, 2026: 4.50]),
    CPTCode(id: 10, code: "99292", description: "Critical care, each additional 30 minutes", profiles: [.criticalCare], rvusByYear: [2020: 2.25, 2024: 2.25, 2026: 2.25]),
    CPTCode(id: 11, code: "99406", description: "Smoking cessation counseling, 3-10 minutes", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 0.24, 2024: 0.24, 2026: 0.24]),
    CPTCode(id: 12, code: "99407", description: "Smoking cessation counseling, more than 10 minutes", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 0.50, 2024: 0.50, 2026: 0.50]),
    CPTCode(id: 13, code: "99497", description: "Advance care planning, first 30 minutes", profiles: [.hospitalist, .criticalCare, .pediatricHospitalist, .snfPostAcute], rvusByYear: [2020: 1.50, 2024: 1.50, 2026: 1.50]),
    CPTCode(id: 14, code: "99498", description: "Advance care planning, each additional 30 minutes", profiles: [.hospitalist, .criticalCare, .pediatricHospitalist, .snfPostAcute], rvusByYear: [2020: 1.40, 2024: 1.40, 2026: 1.40]),
    CPTCode(id: 15, code: "99356", description: "Legacy prolonged inpatient service, first hour", profiles: [.hospitalist], rvusByYear: [2020: 1.71], warning: legacyProlongedWarning),
    CPTCode(id: 16, code: "99357", description: "Legacy prolonged inpatient service, each additional 30 minutes", profiles: [.hospitalist], rvusByYear: [2020: 1.71], warning: legacyProlongedWarning),
    CPTCode(id: 17, code: "99234", description: "Same-day hospital or observation admit/discharge, level 1", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 2.56, 2024: 2.00, 2026: 2.00]),
    CPTCode(id: 18, code: "99235", description: "Same-day hospital or observation admit/discharge, level 2", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 3.24, 2024: 3.24, 2026: 3.24]),
    CPTCode(id: 19, code: "99236", description: "Same-day hospital or observation admit/discharge, level 3", profiles: [.hospitalist, .pediatricHospitalist], rvusByYear: [2020: 4.20, 2024: 4.30, 2026: 4.30]),
    CPTCode(id: 20, code: "G0316", description: "Prolonged inpatient or observation E/M, each additional 15 minutes", profiles: [.hospitalist, .criticalCare, .pediatricHospitalist], rvusByYear: [2024: 0.61, 2026: 0.61]),
    CPTCode(id: 21, code: "99281", description: "Emergency department visit, level 1", profiles: [.emergencyMedicine], rvusByYear: [2020: 0.48, 2024: 0.25, 2026: 0.25]),
    CPTCode(id: 22, code: "99282", description: "Emergency department visit, level 2", profiles: [.emergencyMedicine], rvusByYear: [2020: 0.93, 2024: 0.93, 2026: 0.93]),
    CPTCode(id: 23, code: "99283", description: "Emergency department visit, level 3", profiles: [.emergencyMedicine], rvusByYear: [2020: 1.42, 2024: 1.60, 2026: 1.60]),
    CPTCode(id: 24, code: "99284", description: "Emergency department visit, level 4", profiles: [.emergencyMedicine], rvusByYear: [2020: 2.60, 2024: 2.74, 2026: 2.74]),
    CPTCode(id: 25, code: "99285", description: "Emergency department visit, level 5", profiles: [.emergencyMedicine], rvusByYear: [2020: 3.80, 2024: 4.00, 2026: 4.00]),
    CPTCode(id: 26, code: "99471", description: "Pediatric critical care, initial inpatient, age 29 days-24 months", profiles: [.pediatricCriticalCare], rvusByYear: [2020: 15.98, 2024: 15.98, 2026: 15.98]),
    CPTCode(id: 27, code: "99472", description: "Pediatric critical care, subsequent inpatient, age 29 days-24 months", profiles: [.pediatricCriticalCare], rvusByYear: [2020: 7.99, 2024: 7.99, 2026: 7.99]),
    CPTCode(id: 28, code: "99475", description: "Pediatric critical care, initial inpatient, age 2-5 years", profiles: [.pediatricCriticalCare], rvusByYear: [2020: 11.25, 2024: 11.25, 2026: 11.25]),
    CPTCode(id: 29, code: "99476", description: "Pediatric critical care, subsequent inpatient, age 2-5 years", profiles: [.pediatricCriticalCare], rvusByYear: [2020: 6.75, 2024: 6.75, 2026: 6.75]),
    CPTCode(id: 30, code: "99468", description: "Neonatal critical care, initial inpatient, 28 days or younger", profiles: [.neonatology], rvusByYear: [2020: 18.46, 2024: 18.46, 2026: 18.46]),
    CPTCode(id: 31, code: "99469", description: "Neonatal critical care, subsequent inpatient, 28 days or younger", profiles: [.neonatology], rvusByYear: [2020: 7.99, 2024: 7.99, 2026: 7.99]),
    CPTCode(id: 32, code: "99304", description: "Initial nursing facility care, level 1", profiles: [.snfPostAcute], rvusByYear: [2020: 1.64, 2024: 1.50, 2026: 1.50]),
    CPTCode(id: 33, code: "99305", description: "Initial nursing facility care, level 2", profiles: [.snfPostAcute], rvusByYear: [2020: 2.35, 2024: 2.50, 2026: 2.50]),
    CPTCode(id: 34, code: "99306", description: "Initial nursing facility care, level 3", profiles: [.snfPostAcute], rvusByYear: [2020: 3.06, 2024: 3.50, 2026: 3.50]),
    CPTCode(id: 35, code: "99307", description: "Subsequent nursing facility care, level 1", profiles: [.snfPostAcute], rvusByYear: [2020: 0.76, 2024: 0.70, 2026: 0.70]),
    CPTCode(id: 36, code: "99308", description: "Subsequent nursing facility care, level 2", profiles: [.snfPostAcute], rvusByYear: [2020: 1.16, 2024: 1.30, 2026: 1.30]),
    CPTCode(id: 37, code: "99309", description: "Subsequent nursing facility care, level 3", profiles: [.snfPostAcute], rvusByYear: [2020: 1.55, 2024: 1.92, 2026: 1.92]),
    CPTCode(id: 38, code: "99310", description: "Subsequent nursing facility care, level 4", profiles: [.snfPostAcute], rvusByYear: [2020: 2.35, 2024: 2.80, 2026: 2.80]),
    CPTCode(id: 39, code: "99315", description: "Nursing facility discharge, 30 minutes or less", profiles: [.snfPostAcute], rvusByYear: [2020: 1.28, 2024: 1.50, 2026: 1.50]),
    CPTCode(id: 40, code: "99316", description: "Nursing facility discharge, more than 30 minutes", profiles: [.snfPostAcute], rvusByYear: [2020: 1.90, 2024: 2.50, 2026: 2.50]),
    CPTCode(id: 41, code: "G0317", description: "Prolonged nursing facility E/M, each additional 15 minutes", profiles: [.snfPostAcute], rvusByYear: [2024: 0.61, 2026: 0.61]),
    CPTCode(id: 42, code: "99252", description: "Inpatient or observation consultation, level 2", profiles: [.consultPayerDependent], rvusByYear: [2020: 1.50, 2024: 1.50, 2026: 1.50], warning: consultWarning),
    CPTCode(id: 43, code: "99253", description: "Inpatient or observation consultation, level 3", profiles: [.consultPayerDependent], rvusByYear: [2020: 2.27, 2024: 2.00, 2026: 2.00], warning: consultWarning),
    CPTCode(id: 44, code: "99254", description: "Inpatient or observation consultation, level 4", profiles: [.consultPayerDependent], rvusByYear: [2020: 3.29, 2024: 2.72, 2026: 2.72], warning: consultWarning),
    CPTCode(id: 45, code: "99255", description: "Inpatient or observation consultation, level 5", profiles: [.consultPayerDependent], rvusByYear: [2020: 4.00, 2024: 3.86, 2026: 3.86], warning: consultWarning)
]
