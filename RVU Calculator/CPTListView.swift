//
//  CPTListView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 2/7/26.
//
import SwiftUI
import SwiftData

private extension Color {
    // Cross-platform background color helpers keep the SwiftUI views usable on
    // both iOS and macOS without scattering #if checks through the UI code.
    static var rvuSystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var rvuSecondarySystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private extension View {
    // iOS has a useful inline navigation title style; macOS ignores it.
    @ViewBuilder
    func rvuInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// AppStorage key used to remember the selected WorkProfile UUID string.
private let activeWorkProfileIDKey = "activeWorkProfileID"
private let defaultWorkProfileName = "Default"

// Earlier profile builds used this starter name; keep it only for migration.
private let legacyDefaultWorkProfileName = "Current Job"

// Main landing screen: calendar, schedule controls, month totals, and year summary entry.
struct CPTListView: View {
    @Environment(\.modelContext) private var modelContext

    // SwiftData automatically keeps this list updated when charge records change.
    @Query(sort: \DayRecord.date) private var records: [DayRecord]

    // Available saved work profiles, ordered by creation date for stable menus.
    @Query(sort: \WorkProfile.createdAt) private var workProfiles: [WorkProfile]

    // Profile and schedule preferences are still stored in AppStorage for the
    // shared controls, then mirrored into the active WorkProfile.
    @AppStorage(activeWorkProfileIDKey) private var activeWorkProfileID = ""
    @AppStorage("selectedProviderProfile") private var selectedProfileRaw = ProviderProfile.hospitalist.rawValue
    @AppStorage("rvuScheduleMode") private var scheduleModeRaw = RVUScheduleMode.compare.rawValue
    @AppStorage("singleRVUYear") private var singleRVUYear = 2026
    @AppStorage("baseRVUYear") private var baseRVUYear = 2024
    @AppStorage("comparisonRVUYear") private var comparisonRVUYear = 2026

    @State private var selectedDate = Date()
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var displayedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    // Used for the "Enter Charges for..." button label.
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    // Converts the persisted schedule settings into the years the math/rendering code needs.
    private var selectedScheduleYears: [Int] {
        selectedRVUYears(
            modeRaw: scheduleModeRaw,
            singleYear: singleRVUYear,
            baseYear: baseRVUYear,
            comparisonYear: comparisonRVUYear
        )
    }

    private var activeWorkProfile: WorkProfile? {
        workProfiles.first { $0.id.uuidString == activeWorkProfileID } ?? workProfiles.first
    }

    // Toolbar label for the profile/preferences entry point.
    private var activeWorkProfileName: String {
        activeWorkProfile?.name ?? defaultWorkProfileName
    }

    // ## Formats a year value for display without locale-specific punctuation.
    private func plainYearString(_ year: Int) -> String {
        String(year)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RVUCalendarView(
                    selectedDate: $selectedDate,
                    displayedMonth: $displayedMonth,
                    datesWithEntries: Set(records.map(\.dayKey))
                )
                    .padding(12)
                    .background(Color.rvuSystemBackground)
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

                ScheduleControls()

                monthTotalCard

                yearSection
            }
            .padding(16)
        }
        .navigationTitle("RVU Calculator")
        .toolbar {
            // Opens the profile/preferences page from the main calendar screen.
            NavigationLink {
                WorkProfileSettingsView()
            } label: {
                Label(activeWorkProfileName, systemImage: "person.crop.circle")
            }
        }
        .onAppear(perform: ensureActiveWorkProfile)
        .onChange(of: selectedDate) { _, newDate in
            selectedYear = Calendar.current.component(.year, from: newDate)
        }
        .onChange(of: displayedMonth) { _, newMonth in
            selectedYear = Calendar.current.component(.year, from: newMonth)
        }
        .onChange(of: activeWorkProfileID) { _, _ in
            applyActiveWorkProfileSettings()
        }
        .onChange(of: selectedProfileRaw) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: scheduleModeRaw) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: singleRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: baseRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: comparisonRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
    }

    // Shows the visible calendar month's running RVU total using the active schedule mode.
    private var monthTotalCard: some View {
        let totals = monthTotals(records: records, containing: displayedMonth, years: selectedScheduleYears)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Month Totals")
                .font(.headline)

            Text(totals.monthLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                ForEach(Array(selectedScheduleYears.enumerated()), id: \.element) { index, year in
                    totalChip(
                        title: String(year),
                        value: totals.totalsByYear[year, default: 0],
                        tint: index == 0 ? Color.blue.opacity(0.12) : Color.green.opacity(0.12)
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvuSecondarySystemBackground)
        .cornerRadius(12)
    }

    // Lets the user jump to a month-by-month summary for the selected calendar year.
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
                YearSummaryView(year: selectedYear, scheduleYears: selectedScheduleYears)
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
        .background(Color.rvuSecondarySystemBackground)
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

    // Creates or selects the Default profile, then assigns older unowned records
    // to it. This keeps existing user data available before profile filtering is added.
    private func ensureActiveWorkProfile() {
        let defaultProfile = ensureDefaultWorkProfile()

        if activeWorkProfileID.isEmpty || !workProfiles.contains(where: { $0.id.uuidString == activeWorkProfileID }) {
            activeWorkProfileID = defaultProfile.id.uuidString
            applyActiveWorkProfileSettings()
        }

        assignUnownedRecords(to: defaultProfile)
    }

    // Returns the Default profile, creating it for new installs or renaming the
    // legacy first-run profile from the earlier implementation pass.
    private func ensureDefaultWorkProfile() -> WorkProfile {
        if let defaultProfile = workProfiles.first(where: { $0.name == defaultWorkProfileName }) {
            return defaultProfile
        }

        if let legacyProfile = workProfiles.first(where: { $0.name == legacyDefaultWorkProfileName }) {
            legacyProfile.name = defaultWorkProfileName
            try? modelContext.save()
            return legacyProfile
        }

        let profile = WorkProfile(
            name: defaultWorkProfileName,
            providerProfile: ProviderProfile(rawValue: selectedProfileRaw) ?? .hospitalist,
            scheduleMode: RVUScheduleMode(rawValue: scheduleModeRaw) ?? .compare,
            singleRVUYear: singleRVUYear,
            baseRVUYear: baseRVUYear,
            comparisonRVUYear: comparisonRVUYear
        )
        modelContext.insert(profile)
        activeWorkProfileID = profile.id.uuidString
        try? modelContext.save()
        return profile
    }

    // Marks records created before profiles existed as belonging to Default.
    private func assignUnownedRecords(to profile: WorkProfile) {
        var updatedRecord = false
        for record in records where record.workProfileID == nil {
            record.workProfileID = profile.id
            updatedRecord = true
        }

        if updatedRecord {
            try? modelContext.save()
        }
    }

    // Loads the selected profile's saved specialty and RVU schedule preferences
    // back into the existing AppStorage-backed controls.
    private func applyActiveWorkProfileSettings() {
        guard let profile = activeWorkProfile else { return }
        selectedProfileRaw = profile.providerProfileRaw
        scheduleModeRaw = profile.scheduleModeRaw
        singleRVUYear = profile.singleRVUYear
        baseRVUYear = profile.baseRVUYear
        comparisonRVUYear = profile.comparisonRVUYear
    }

    // Persists changes from the shared specialty/schedule controls onto the
    // active profile so switching profiles restores each job's preferences.
    private func saveCurrentSettingsToActiveWorkProfile() {
        guard let profile = activeWorkProfile else { return }
        profile.providerProfileRaw = selectedProfileRaw
        profile.scheduleModeRaw = scheduleModeRaw
        profile.singleRVUYear = singleRVUYear
        profile.baseRVUYear = baseRVUYear
        profile.comparisonRVUYear = comparisonRVUYear
        try? modelContext.save()
    }
}

// Profile management screen. Profiles now own both preferences and migrated
// charge records; later steps will filter the calendar and exports by owner.
private struct WorkProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Profile list shown in the picker and management section.
    @Query(sort: \WorkProfile.createdAt) private var workProfiles: [WorkProfile]

    // Used when assigning older records to Default or reassigning records after deletion.
    @Query(sort: \DayRecord.date) private var records: [DayRecord]

    // Shared settings backing the existing profile and RVU schedule controls.
    @AppStorage(activeWorkProfileIDKey) private var activeWorkProfileID = ""
    @AppStorage("selectedProviderProfile") private var selectedProfileRaw = ProviderProfile.hospitalist.rawValue
    @AppStorage("rvuScheduleMode") private var scheduleModeRaw = RVUScheduleMode.compare.rawValue
    @AppStorage("singleRVUYear") private var singleRVUYear = 2026
    @AppStorage("baseRVUYear") private var baseRVUYear = 2024
    @AppStorage("comparisonRVUYear") private var comparisonRVUYear = 2026

    @State private var newProfileName = ""
    @State private var profilePendingDelete: WorkProfile?

    // Current profile used for the summary rows in the Active Profile section.
    private var activeProfile: WorkProfile? {
        workProfiles.first { $0.id.uuidString == activeWorkProfileID } ?? workProfiles.first
    }

    var body: some View {
        List {
            // Picker for switching the whole app to another saved work context.
            Section("Active Profile") {
                Picker("Profile", selection: $activeWorkProfileID) {
                    ForEach(workProfiles) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                }

                if let activeProfile {
                    profileDetail(profile: activeProfile)
                }
            }

            // Creates a new profile using the current specialty/schedule settings.
            Section("Add Profile") {
                TextField("Profile name", text: $newProfileName)

                Button("Add Profile", action: addProfile)
                    .disabled(trimmedNewProfileName.isEmpty)
            }

            // Rename, duplicate, or remove saved profile definitions.
            Section("Manage Profiles") {
                ForEach(workProfiles) { profile in
                    profileManagementRow(profile)
                }
            }
        }
        .navigationTitle("Profiles")
        .onAppear(perform: ensureProfileExists)
        .onChange(of: activeWorkProfileID) { _, _ in
            applyActiveProfileSettings()
        }
        .alert("Delete Profile?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                profilePendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingProfile()
            }
        } message: {
            Text("Any saved charges assigned to this profile will move to another available profile.")
        }
    }

    private var trimmedNewProfileName: String {
        newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Converts an optional pending-delete profile into the Bool binding required
    // by SwiftUI's alert API.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { profilePendingDelete != nil },
            set: { if !$0 { profilePendingDelete = nil } }
        )
    }

    // Read-only summary of the preferences stored on a profile.
    @ViewBuilder
    private func profileDetail(profile: WorkProfile) -> some View {
        LabeledContent("Default Specialty", value: profile.providerProfile.displayName)
        LabeledContent("RVU Schedule", value: profile.scheduleMode.displayName)
    }

    // One editable row in the Manage Profiles section.
    private func profileManagementRow(_ profile: WorkProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Profile name", text: nameBinding(for: profile))
                .font(.headline)

            HStack {
                Button("Duplicate") {
                    duplicateProfile(profile)
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    profilePendingDelete = profile
                }
                .disabled(workProfiles.count <= 1)
            }
            .font(.subheadline)

            if profile.id.uuidString == activeWorkProfileID {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // Saves inline profile-name edits immediately while avoiding blank names.
    private func nameBinding(for profile: WorkProfile) -> Binding<String> {
        Binding(
            get: { profile.name },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.name = trimmed.isEmpty ? "Untitled Profile" : newValue
                try? modelContext.save()
            }
        )
    }

    // Ensures the settings page has a Default profile and migrates older records
    // that were saved before profiles existed.
    private func ensureProfileExists() {
        let defaultProfile = ensureDefaultWorkProfile()

        if activeWorkProfileID.isEmpty || !workProfiles.contains(where: { $0.id.uuidString == activeWorkProfileID }) {
            activeWorkProfileID = defaultProfile.id.uuidString
            applyActiveProfileSettings()
        }

        assignUnownedRecords(to: defaultProfile)
    }

    // Returns the Default profile, preserving a legacy starter profile by
    // renaming it instead of creating a duplicate.
    private func ensureDefaultWorkProfile() -> WorkProfile {
        if let defaultProfile = workProfiles.first(where: { $0.name == defaultWorkProfileName }) {
            return defaultProfile
        }

        if let legacyProfile = workProfiles.first(where: { $0.name == legacyDefaultWorkProfileName }) {
            legacyProfile.name = defaultWorkProfileName
            try? modelContext.save()
            return legacyProfile
        }

        let profile = WorkProfile(
            name: defaultWorkProfileName,
            providerProfile: ProviderProfile(rawValue: selectedProfileRaw) ?? .hospitalist,
            scheduleMode: RVUScheduleMode(rawValue: scheduleModeRaw) ?? .compare,
            singleRVUYear: singleRVUYear,
            baseRVUYear: baseRVUYear,
            comparisonRVUYear: comparisonRVUYear
        )
        modelContext.insert(profile)
        activeWorkProfileID = profile.id.uuidString
        try? modelContext.save()
        return profile
    }

    // Gives existing records a profile owner exactly once.
    private func assignUnownedRecords(to profile: WorkProfile) {
        var updatedRecord = false
        for record in records where record.workProfileID == nil {
            record.workProfileID = profile.id
            updatedRecord = true
        }

        if updatedRecord {
            try? modelContext.save()
        }
    }

    // Adds a profile from the text field and clears the field afterward.
    private func addProfile() {
        addProfile(named: trimmedNewProfileName)
        newProfileName = ""
    }

    // Creates a profile initialized from the user's current specialty/schedule settings.
    private func addProfile(named name: String) {
        let profile = WorkProfile(
            name: name,
            providerProfile: ProviderProfile(rawValue: selectedProfileRaw) ?? .hospitalist,
            scheduleMode: RVUScheduleMode(rawValue: scheduleModeRaw) ?? .compare,
            singleRVUYear: singleRVUYear,
            baseRVUYear: baseRVUYear,
            comparisonRVUYear: comparisonRVUYear
        )
        modelContext.insert(profile)
        activeWorkProfileID = profile.id.uuidString
        try? modelContext.save()
    }

    // Copies a profile's preferences into a new active profile.
    private func duplicateProfile(_ profile: WorkProfile) {
        let copy = WorkProfile(
            name: "\(profile.name) Copy",
            providerProfile: profile.providerProfile,
            scheduleMode: profile.scheduleMode,
            singleRVUYear: profile.singleRVUYear,
            baseRVUYear: profile.baseRVUYear,
            comparisonRVUYear: profile.comparisonRVUYear
        )
        modelContext.insert(copy)
        activeWorkProfileID = copy.id.uuidString
        try? modelContext.save()
        applyActiveProfileSettings()
    }

    // Deletes the profile selected in the confirmation alert, moving its saved
    // records to the next available profile first.
    private func deletePendingProfile() {
        guard let profile = profilePendingDelete else { return }
        let remainingProfiles = workProfiles.filter { $0.id != profile.id }
        guard !remainingProfiles.isEmpty else {
            profilePendingDelete = nil
            return
        }

        let deletedActiveProfile = profile.id.uuidString == activeWorkProfileID
        let replacementProfile = remainingProfiles[0]

        for record in records where record.workProfileID == profile.id {
            record.workProfileID = replacementProfile.id
        }

        modelContext.delete(profile)

        if deletedActiveProfile {
            activeWorkProfileID = replacementProfile.id.uuidString
            applyActiveProfileSettings()
        }

        try? modelContext.save()
        profilePendingDelete = nil
    }

    // Applies the selected profile's saved preferences to the shared controls.
    private func applyActiveProfileSettings() {
        guard let profile = activeProfile else { return }
        selectedProfileRaw = profile.providerProfileRaw
        scheduleModeRaw = profile.scheduleModeRaw
        singleRVUYear = profile.singleRVUYear
        baseRVUYear = profile.baseRVUYear
        comparisonRVUYear = profile.comparisonRVUYear
    }
}

// Shared helper that turns schedule settings into a non-duplicated list of years.
// If the user picks the same year for base and comparison, the UI collapses to one column.
private func selectedRVUYears(modeRaw: String, singleYear: Int, baseYear: Int, comparisonYear: Int) -> [Int] {
    let mode = RVUScheduleMode(rawValue: modeRaw) ?? .compare
    switch mode {
    case .single:
        return [singleYear]
    case .compare:
        return baseYear == comparisonYear ? [baseYear] : [baseYear, comparisonYear]
    }
}

// Reusable controls for choosing one schedule year or comparing two years.
// This appears on both the calendar screen and the daily charge-entry screen.
private struct ScheduleControls: View {
    @AppStorage("rvuScheduleMode") private var scheduleModeRaw = RVUScheduleMode.compare.rawValue
    @AppStorage("singleRVUYear") private var singleRVUYear = 2026
    @AppStorage("baseRVUYear") private var baseRVUYear = 2024
    @AppStorage("comparisonRVUYear") private var comparisonRVUYear = 2026

    // Picker tags use String raw values because AppStorage stores the selected mode that way.
    private var scheduleMode: Binding<String> {
        Binding(
            get: { scheduleModeRaw },
            set: { scheduleModeRaw = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RVU Schedule")
                .font(.headline)

            Picker("Mode", selection: scheduleMode) {
                ForEach(RVUScheduleMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if (RVUScheduleMode(rawValue: scheduleModeRaw) ?? .compare) == .single {
                yearPicker("Year", selection: $singleRVUYear)
            } else {
                HStack {
                    yearPicker("Base", selection: $baseRVUYear)
                    yearPicker("Compare", selection: $comparisonRVUYear)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvuSecondarySystemBackground)
        .cornerRadius(12)
    }

    // Menu picker is compact enough for the card layout and works on iOS/macOS.
    private func yearPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(supportedRVUYears, id: \.self) { year in
                Text(String(year)).tag(year)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }
}

// Custom month calendar that shows which days already have saved charges.
struct RVUCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let datesWithEntries: Set<String>

    init(selectedDate: Binding<Date>, displayedMonth: Binding<Date>, datesWithEntries: Set<String>) {
        self._selectedDate = selectedDate
        self._displayedMonth = displayedMonth
        self.datesWithEntries = datesWithEntries
    }

    // Display label for the visible calendar month.
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    // Reorders weekday labels to respect the user's current calendar first weekday.
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // Produces a grid with nil leading/trailing slots so month days align under weekdays.
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
        // If the selected date changes elsewhere, keep the visible month in sync.
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

// One tappable day in the custom calendar.
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

// Daily charge-entry workflow: profile-specific list, full-catalog search, save, and results.
struct DayChargeEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Used to keep daily-entry specialty/schedule edits synced with the active profile.
    @Query(sort: \WorkProfile.createdAt) private var workProfiles: [WorkProfile]

    // Profile and schedule choices are remembered globally so daily entry stays fast.
    @AppStorage(activeWorkProfileIDKey) private var activeWorkProfileID = ""
    @AppStorage("selectedProviderProfile") private var selectedProfileRaw = ProviderProfile.hospitalist.rawValue
    @AppStorage("rvuScheduleMode") private var scheduleModeRaw = RVUScheduleMode.compare.rawValue
    @AppStorage("singleRVUYear") private var singleRVUYear = 2026
    @AppStorage("baseRVUYear") private var baseRVUYear = 2024
    @AppStorage("comparisonRVUYear") private var comparisonRVUYear = 2026

    let date: Date

    // Text values are stored while editing so empty fields can stay visually empty.
    @State private var chargeCounts: [Int: String] = [:]

    // Tracks searched/added codes that are outside the active profile but should be visible today.
    @State private var extraCodeIDs: Set<Int> = []
    @State private var searchText = ""
    @State private var statusMessage: String?
    @State private var summaryTotalsByYear: [Int: Double] = [:]
    @State private var summaryRows: [CPTSummary] = []
    @State private var showSummary = false

    // Used for the navigation title on the daily entry screen.
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    // Converts the stored raw profile value into the enum used by filtering logic.
    private var selectedProfile: ProviderProfile {
        ProviderProfile(rawValue: selectedProfileRaw) ?? .hospitalist
    }

    // Active profile for saving daily-entry preference changes.
    private var activeWorkProfile: WorkProfile? {
        workProfiles.first { $0.id.uuidString == activeWorkProfileID } ?? workProfiles.first
    }

    // Active schedule years for result calculations.
    private var selectedScheduleYears: [Int] {
        selectedRVUYears(
            modeRaw: scheduleModeRaw,
            singleYear: singleRVUYear,
            baseYear: baseRVUYear,
            comparisonYear: comparisonRVUYear
        )
    }

    // The normal charge rows for the selected provider profile.
    private var profileCodes: [CPTCode] {
        cptCodes.filter { $0.profiles.contains(selectedProfile) }
    }

    // Rows outside the active profile that have been searched/added or already have counts.
    // This prevents profile switching from hiding saved charges.
    private var additionalCodes: [CPTCode] {
        cptCodes.filter { cpt in
            !cpt.profiles.contains(selectedProfile)
                && (extraCodeIDs.contains(cpt.id) || ((Int(chargeCounts[cpt.id, default: ""]) ?? 0) > 0))
        }
    }

    // Search only offers catalog rows that are not already visible on the screen.
    private var searchResults: [CPTCode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return cptCodes
            .filter { cpt in
                !cpt.profiles.contains(selectedProfile)
                    && !additionalCodes.contains { $0.id == cpt.id }
                    && (cpt.code.localizedCaseInsensitiveContains(query)
                        || cpt.description.localizedCaseInsensitiveContains(query))
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            profilePicker
                .padding(.horizontal)

            ScheduleControls()
                .padding(.horizontal)

            List {
                Section("Profile Codes") {
                    ForEach(profileCodes) { cpt in
                        codeRow(for: cpt)
                    }
                }

                Section("Search All Codes") {
                    TextField("Search CPT or description", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ForEach(searchResults) { cpt in
                        Button {
                            extraCodeIDs.insert(cpt.id)
                            chargeCounts[cpt.id, default: ""] = chargeCounts[cpt.id, default: ""]
                            searchText = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cpt.code)
                                    .font(.headline)
                                Text(cpt.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if !additionalCodes.isEmpty {
                    Section("Additional Charged Codes") {
                        ForEach(additionalCodes) { cpt in
                            codeRow(for: cpt)
                        }
                    }
                }
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
        .rvuInlineNavigationTitle()
        .onAppear {
            applyActiveWorkProfileSettings()
            loadForDate()
        }
        .onChange(of: selectedProfileRaw) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: scheduleModeRaw) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: singleRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: baseRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .onChange(of: comparisonRVUYear) { _, _ in
            saveCurrentSettingsToActiveWorkProfile()
        }
        .sheet(isPresented: $showSummary) {
            NavigationStack {
                ResultView(
                    scheduleYears: selectedScheduleYears,
                    totalsByYear: summaryTotalsByYear,
                    cptSummaries: summaryRows,
                    onReturnToCalendar: {
                        showSummary = false
                        dismiss()
                    }
                )
            }
        }
    }

    // Restores the active profile's specialty/schedule settings before loading rows.
    private func applyActiveWorkProfileSettings() {
        guard let profile = activeWorkProfile else { return }
        selectedProfileRaw = profile.providerProfileRaw
        scheduleModeRaw = profile.scheduleModeRaw
        singleRVUYear = profile.singleRVUYear
        baseRVUYear = profile.baseRVUYear
        comparisonRVUYear = profile.comparisonRVUYear
    }

    // Captures changes made from the daily charge-entry controls on the active profile.
    private func saveCurrentSettingsToActiveWorkProfile() {
        guard let profile = activeWorkProfile else { return }
        profile.providerProfileRaw = selectedProfileRaw
        profile.scheduleModeRaw = scheduleModeRaw
        profile.singleRVUYear = singleRVUYear
        profile.baseRVUYear = baseRVUYear
        profile.comparisonRVUYear = comparisonRVUYear
        try? modelContext.save()
    }

    // Compact profile selector shown above the daily charge list.
    private var profilePicker: some View {
        HStack {
            Text("Profile")
                .font(.headline)

            Spacer()

            Picker("Profile", selection: $selectedProfileRaw) {
                ForEach(ProviderProfile.allCases) { profile in
                    Text(profile.displayName).tag(profile.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // Shared row layout for profile rows and additional searched rows.
    private func codeRow(for cpt: CPTCode) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cpt.code)
                    .font(.headline)
                Text(cpt.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let warning = cpt.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            countField(for: cpt)
        }
        .padding(.vertical, 4)
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

    // ## Keeps the row input portable while preserving the iOS numeric keyboard.
    @ViewBuilder
    private func countField(for cpt: CPTCode) -> some View {
        #if os(iOS)
        TextField("0", text: binding(for: cpt))
            .font(.body.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            .frame(width: 80)
            .textFieldStyle(.roundedBorder)
        #else
        TextField("0", text: binding(for: cpt))
            .font(.body.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .textFieldStyle(.roundedBorder)
        #endif
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
        extraCodeIDs = Set(stored.keys).subtracting(profileCodes.map(\.id))
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
                    // Backfill the owner if this day was created before profiles existed.
                    if existing.workProfileID == nil {
                        existing.workProfileID = activeWorkProfile?.id
                    }
                }
            } else if !normalized.isEmpty {
                // New records are tagged now; filtering by active profile comes next.
                modelContext.insert(DayRecord(date: date, counts: normalized, workProfileID: activeWorkProfile?.id))
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

            let totalsByYear = selectedScheduleYears.reduce(into: [Int: Double]()) { partialResult, year in
                if let rvu = cpt.rvu(for: year) {
                    partialResult[year] = Double(count) * rvu
                }
            }

            return CPTSummary(
                id: cpt.id,
                code: cpt.code,
                count: count,
                totalsByYear: totalsByYear,
                warning: cpt.warning
            )
        }

        summaryRows = summaries
        summaryTotalsByYear = selectedScheduleYears.reduce(into: [Int: Double]()) { partialResult, year in
            partialResult[year] = summaries.reduce(0.0) { $0 + $1.totalsByYear[year, default: 0] }
        }
    }
}

// Month-by-month totals for a selected calendar year and active RVU schedule setting.
struct YearSummaryView: View {
    @Query(sort: \DayRecord.date) private var records: [DayRecord]

    let year: Int
    let scheduleYears: [Int]

    // Navigation title helper that avoids locale punctuation in the year.
    private var plainYearString: String {
        String(year)
    }

    var body: some View {
        let perMonth = monthlyTotals(records: records, year: year, scheduleYears: scheduleYears)

        List {
            Section {
                ForEach(perMonth) { month in
                    HStack {
                        Text(month.monthName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(scheduleYears, id: \.self) { scheduleYear in
                            Text("\(month.totalsByYear[scheduleYear, default: 0], specifier: "%.2f")")
                                .font(.body.monospacedDigit())
                                .frame(width: 96, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text("Month")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(scheduleYears, id: \.self) { scheduleYear in
                        Text(String(scheduleYear))
                            .frame(width: 96, alignment: .trailing)
                    }
                }
                .font(.subheadline.bold())
            }

            Section("Year Total") {
                HStack {
                    Text("Total")
                    Spacer()
                    ForEach(scheduleYears, id: \.self) { scheduleYear in
                        Text("\(perMonth.reduce(0.0) { $0 + $1.totalsByYear[scheduleYear, default: 0] }, specifier: "%.2f")")
                            .font(.body.monospacedDigit())
                            .frame(width: 96, alignment: .trailing)
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("\(plainYearString) Monthly RVUs")
    }
}
