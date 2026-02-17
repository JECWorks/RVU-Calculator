//
//  CPTListView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 2/7/26.
//
import SwiftUI
import SwiftData

struct CPTListView: View {
    @Query(sort: \DayRecord.date) private var records: [DayRecord]

    @State private var selectedDate = Date()
    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    // ## Formats a year value for display without locale-specific punctuation.
    private func plainYearString(_ year: Int) -> String {
        String(year)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RVUCalendarView(
                    selectedDate: $selectedDate,
                    datesWithEntries: Set(records.map(\.dayKey))
                )
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

                NavigationLink {
                    DayChargeEntryView(date: selectedDate)
                } label: {
                    Text("Enter Charges for \(dayFormatter.string(from: selectedDate))")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                monthTotalCard

                yearSection
            }
            .padding(16)
        }
        .navigationTitle("RVU Calculator")
        .onChange(of: selectedDate) { _, newDate in
            selectedYear = Calendar.current.component(.year, from: newDate)
        }
    }

    private var monthTotalCard: some View {
        let totals = monthTotals(records: records, containing: selectedDate)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Month Totals")
                .font(.headline)

            Text(totals.monthLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                totalChip(title: "2020", value: totals.total2020, tint: Color.blue.opacity(0.12))
                totalChip(title: "2024", value: totals.total2024, tint: Color.green.opacity(0.12))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Year View")
                    .font(.headline)

                Spacer()

                Stepper("", value: $selectedYear, in: 2020...2100)
                    .labelsHidden()

                Text(plainYearString(selectedYear))
                    .font(.subheadline.monospacedDigit())
            }

            NavigationLink {
                YearSummaryView(year: selectedYear)
            } label: {
                Text("View Monthly RVUs")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.teal)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // ## Renders a compact metric chip for monthly RVU totals.
    private func totalChip(title: String, value: Double, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\(value, specifier: "%.2f")")
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(tint)
        .cornerRadius(10)
    }
}

struct RVUCalendarView: View {
    @Binding var selectedDate: Date
    let datesWithEntries: Set<String>

    @State private var displayedMonth: Date

    init(selectedDate: Binding<Date>, datesWithEntries: Set<String>) {
        self._selectedDate = selectedDate
        self.datesWithEntries = datesWithEntries
        let month = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        ) ?? selectedDate.wrappedValue
        self._displayedMonth = State(initialValue: month)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var dayGrid: [Date?] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ) ?? displayedMonth
        let dayRange = calendar.range(of: .day, in: .month, for: startOfMonth) ?? 1..<2
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingSlots = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days = Array<Date?>(repeating: nil, count: leadingSlots)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    if let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = newMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    if let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = newMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(dayGrid.enumerated()), id: \.offset) { _, value in
                    if let date = value {
                        DayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            hasEntry: datesWithEntries.contains(DayRecord.key(for: date))
                        ) {
                            selectedDate = date
                            displayedMonth = Calendar.current.date(
                                from: Calendar.current.dateComponents([.year, .month], from: date)
                            ) ?? date
                        }
                    } else {
                        Color.clear
                            .frame(height: 32)
                    }
                }
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            let selectedMonth = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: newDate)
            ) ?? newDate
            if !Calendar.current.isDate(selectedMonth, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = selectedMonth
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasEntry: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.body.monospacedDigit())
                .fontWeight(hasEntry ? .bold : .regular)
                .foregroundColor(isSelected ? .white : (hasEntry ? .green : .primary))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DayChargeEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var chargeCounts: [Int: String] = [:]
    @State private var statusMessage: String?
    @State private var summaryTotals2020: Double = 0
    @State private var summaryTotals2024: Double = 0
    @State private var summaryRows: [CPTSummary] = []
    @State private var showSummary = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CPT")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Count")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal)

            Divider()

            List(cptCodes) { cpt in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cpt.code)
                            .font(.headline)
                        Text(cpt.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    TextField("0", text: binding(for: cpt))
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)

            HStack(spacing: 10) {
                Button(action: saveCharges) {
                    Text("Save Charges")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: { dismiss() }) {
                    Text("Back to Calendar")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            if let statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(dateFormatter.string(from: date))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadForDate)
        .sheet(isPresented: $showSummary) {
            NavigationStack {
                ResultView(
                    totalRVUs2020: summaryTotals2020,
                    totalRVUs2024: summaryTotals2024,
                    cptSummaries: summaryRows,
                    onReturnToCalendar: {
                        showSummary = false
                        dismiss()
                    }
                )
            }
        }
    }

    // ## Provides numeric-only text binding for a CPT row count input.
    private func binding(for cpt: CPTCode) -> Binding<String> {
        Binding(
            get: { chargeCounts[cpt.id, default: ""] },
            set: { newValue in
                chargeCounts[cpt.id] = newValue.filter(\.isNumber)
                statusMessage = nil
            }
        )
    }

    // ## Loads saved charge counts for the selected day into editable state.
    private func loadForDate() {
        let key = DayRecord.key(for: date)
        var descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1

        let stored = (try? modelContext.fetch(descriptor).first)?.counts ?? [:]

        chargeCounts = Dictionary(uniqueKeysWithValues: cptCodes.map { cpt in
            let count = stored[cpt.id] ?? 0
            return (cpt.id, count == 0 ? "" : String(count))
        })
    }

    // ## Persists current day charges and presents the calculated result summary.
    private func saveCharges() {
        let normalized = chargeCounts.reduce(into: [Int: Int]()) { partialResult, item in
            let count = Int(item.value) ?? 0
            if count > 0 {
                partialResult[item.key] = count
            }
        }

        let key = DayRecord.key(for: date)
        var descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1

        do {
            let existing = try modelContext.fetch(descriptor).first

            if let existing {
                if normalized.isEmpty {
                    modelContext.delete(existing)
                } else {
                    existing.date = DayRecord.startOfDay(for: date)
                    existing.counts = normalized
                }
            } else if !normalized.isEmpty {
                modelContext.insert(DayRecord(date: date, counts: normalized))
            }

            try modelContext.save()
            statusMessage = nil
            buildSummary(from: normalized)
            showSummary = true
        } catch {
            statusMessage = "Unable to save. Please try again."
        }
    }

    // ## Builds per-code and total RVU summary values from normalized charge counts.
    private func buildSummary(from counts: [Int: Int]) {
        let summaries = cptCodes.compactMap { cpt -> CPTSummary? in
            let count = counts[cpt.id] ?? 0
            guard count > 0 else { return nil }

            return CPTSummary(
                id: cpt.id,
                code: cpt.code,
                count: count,
                total2020: Double(count) * cpt.rvu2020,
                total2024: Double(count) * cpt.rvu2024
            )
        }

        summaryRows = summaries
        summaryTotals2020 = summaries.reduce(0.0) { $0 + $1.total2020 }
        summaryTotals2024 = summaries.reduce(0.0) { $0 + $1.total2024 }
    }
}

struct YearSummaryView: View {
    @Query(sort: \DayRecord.date) private var records: [DayRecord]

    let year: Int

    private var plainYearString: String {
        String(year)
    }

    var body: some View {
        let perMonth = monthlyTotals(records: records, year: year)

        List {
            Section {
                ForEach(perMonth) { month in
                    HStack {
                        Text(month.monthName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(month.total2020, specifier: "%.2f")")
                            .font(.body.monospacedDigit())
                            .frame(width: 96, alignment: .trailing)

                        Text("\(month.total2024, specifier: "%.2f")")
                            .font(.body.monospacedDigit())
                            .frame(width: 96, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text("Month")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("2020")
                        .frame(width: 96, alignment: .trailing)
                    Text("2024")
                        .frame(width: 96, alignment: .trailing)
                }
                .font(.subheadline.bold())
            }

            Section("Year Total") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(perMonth.reduce(0.0) { $0 + $1.total2020 }, specifier: "%.2f")")
                        .font(.body.monospacedDigit())
                        .frame(width: 96, alignment: .trailing)
                    Text("\(perMonth.reduce(0.0) { $0 + $1.total2024 }, specifier: "%.2f")")
                        .font(.body.monospacedDigit())
                        .frame(width: 96, alignment: .trailing)
                }
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("\(plainYearString) Monthly RVUs")
    }
}
