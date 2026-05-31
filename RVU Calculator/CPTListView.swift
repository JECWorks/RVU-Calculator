//
//  CPTListView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 2/7/26.
//
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

// Simple text-backed document used by the system file exporter for CSV output.
private struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// Destination-date behavior when moving a saved charge record.
private enum MoveChargeMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }
}

// Whether a profile transfer removes the original record or leaves it in place.
private enum ProfileTransferAction: String, CaseIterable, Identifiable {
    case move
    case copy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .move: "Move"
        case .copy: "Copy"
        }
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

    // String form used in SwiftData predicates for profile/date lookups.
    private var activeWorkProfileIDString: String {
        activeWorkProfile?.id.uuidString ?? activeWorkProfileID
    }

    // Records currently visible in the calendar and summary cards.
    private var activeProfileRecords: [DayRecord] {
        guard let activeProfileIDString = activeWorkProfile?.id.uuidString else { return [] }
        return records.filter { $0.workProfileIDString == activeProfileIDString }
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
                    datesWithEntries: Set(activeProfileRecords.map(\.dayKey))
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
                PreferencesView()
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

    // Shows the visible calendar month's running RVU total for the active profile.
    private var monthTotalCard: some View {
        let totals = monthTotals(records: activeProfileRecords, containing: displayedMonth, years: selectedScheduleYears)

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
                YearSummaryView(year: selectedYear, scheduleYears: selectedScheduleYears, workProfileIDString: activeWorkProfile?.id.uuidString)
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

// Preferences screen for profile selection, profile defaults, and saved-profile management.
private struct PreferencesView: View {
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
    @State private var csvDocument = CSVExportDocument()
    @State private var csvFilename = "RVU-Export.csv"
    @State private var isExportingCSV = false
    @State private var exportStatusMessage: String?
    @State private var resetScopePendingConfirmation: ResetScope?

    // Charge-data reset choices shown through a single confirmation alert.
    private enum ResetScope {
        case activeProfile
        case allProfiles
    }

    // Current profile used for the active profile summary and defaults.
    private var activeProfile: WorkProfile? {
        workProfiles.first { $0.id.uuidString == activeWorkProfileID } ?? workProfiles.first
    }

    // Active profile's records, used for a quick data-footprint summary.
    private var activeProfileRecords: [DayRecord] {
        guard let activeProfileIDString = activeProfile?.id.uuidString else { return [] }
        return records.filter { $0.workProfileIDString == activeProfileIDString }
    }

    // Any saved charge records, sorted by date for export and reset summaries.
    private var allChargeRecords: [DayRecord] {
        records.sorted { $0.date < $1.date }
    }

    // Binding for the schedule mode segmented control.
    private var scheduleMode: Binding<String> {
        Binding(
            get: { scheduleModeRaw },
            set: { scheduleModeRaw = $0 }
        )
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

            // Default entry settings restored whenever this profile becomes active.
            Section("Profile Defaults") {
                profileDefaultControls
            }

            // Export and reset charge data without changing saved profile definitions.
            Section("Data Management") {
                dataManagementControls
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
        .navigationTitle("Preferences")
        .onAppear(perform: ensureProfileExists)
        .onChange(of: activeWorkProfileID) { _, _ in
            applyActiveProfileSettings()
        }
        .onChange(of: selectedProfileRaw) { _, _ in
            saveCurrentSettingsToActiveProfile()
        }
        .onChange(of: scheduleModeRaw) { _, _ in
            saveCurrentSettingsToActiveProfile()
        }
        .onChange(of: singleRVUYear) { _, _ in
            saveCurrentSettingsToActiveProfile()
        }
        .onChange(of: baseRVUYear) { _, _ in
            saveCurrentSettingsToActiveProfile()
        }
        .onChange(of: comparisonRVUYear) { _, _ in
            saveCurrentSettingsToActiveProfile()
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
        .alert("Reset Charge Data?", isPresented: resetAlertBinding) {
            Button("Cancel", role: .cancel) {
                resetScopePendingConfirmation = nil
            }
            Button("Delete Charges", role: .destructive) {
                performPendingReset()
            }
        } message: {
            Text(resetAlertMessage)
        }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: csvFilename
        ) { result in
            switch result {
            case .success:
                exportStatusMessage = "CSV export ready."
            case .failure:
                exportStatusMessage = "Unable to export CSV."
            }
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

    // Bridges the pending reset action into SwiftUI's Bool-based alert API.
    private var resetAlertBinding: Binding<Bool> {
        Binding(
            get: { resetScopePendingConfirmation != nil },
            set: { if !$0 { resetScopePendingConfirmation = nil } }
        )
    }

    // Message shown before deleting saved charge records.
    private var resetAlertMessage: String {
        switch resetScopePendingConfirmation {
        case .activeProfile:
            return "This deletes saved charges for \(activeProfile?.name ?? defaultWorkProfileName). Profile settings will remain."
        case .allProfiles:
            return "This deletes saved charges from every profile. Profile settings will remain."
        case nil:
            return ""
        }
    }

    // Read-only summary of the preferences stored on a profile.
    @ViewBuilder
    private func profileDetail(profile: WorkProfile) -> some View {
        LabeledContent("Saved Days", value: String(activeProfileRecords.count))
        LabeledContent("Created", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
    }

    // Editable defaults for the profile currently selected above.
    private var profileDefaultControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Default Specialty", selection: $selectedProfileRaw) {
                ForEach(ProviderProfile.allCases) { profile in
                    Text(profile.displayName).tag(profile.rawValue)
                }
            }

            Picker("RVU Schedule", selection: scheduleMode) {
                ForEach(RVUScheduleMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if (RVUScheduleMode(rawValue: scheduleModeRaw) ?? .compare) == .single {
                preferenceYearPicker("Default Year", selection: $singleRVUYear)
            } else {
                HStack {
                    preferenceYearPicker("Base Year", selection: $baseRVUYear)
                    preferenceYearPicker("Compare Year", selection: $comparisonRVUYear)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // Compact schedule-year picker used inside the Preferences list.
    private func preferenceYearPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(supportedRVUYears, id: \.self) { year in
                Text(String(year)).tag(year)
            }
        }
        .pickerStyle(.menu)
    }

    // Buttons for exporting CSVs and clearing saved charge data.
    private var dataManagementControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Export Current Profile CSV") {
                exportCSV(records: activeProfileRecords, filename: csvFilename(for: activeProfile?.name ?? defaultWorkProfileName))
            }
            .disabled(activeProfileRecords.isEmpty)

            Button("Export All Profiles CSV") {
                exportCSV(records: allChargeRecords, filename: "RVU-All-Profiles.csv")
            }
            .disabled(allChargeRecords.isEmpty)

            Divider()

            Button("Delete Current Profile Charges", role: .destructive) {
                resetScopePendingConfirmation = .activeProfile
            }
            .disabled(activeProfileRecords.isEmpty)

            Button("Delete All Charge Data", role: .destructive) {
                resetScopePendingConfirmation = .allProfiles
            }
            .disabled(allChargeRecords.isEmpty)

            if let exportStatusMessage {
                Text(exportStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    // Prepares the CSV document and opens the system export sheet.
    private func exportCSV(records recordsToExport: [DayRecord], filename: String) {
        csvDocument = CSVExportDocument(text: csvText(for: recordsToExport))
        csvFilename = filename
        exportStatusMessage = nil
        isExportingCSV = true
    }

    // Builds one CSV row per charged CPT code so spreadsheet summaries stay easy.
    private func csvText(for recordsToExport: [DayRecord]) -> String {
        let cptByID = Dictionary(uniqueKeysWithValues: cptCodes.map { ($0.id, $0) })
        let profileNamesByID = Dictionary(uniqueKeysWithValues: workProfiles.map { ($0.id.uuidString, $0.name) })
        let header = csvHeader()

        let rows = recordsToExport
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return (lhs.workProfileIDString ?? "") < (rhs.workProfileIDString ?? "")
                }
                return lhs.date < rhs.date
            }
            .flatMap { record in
                record.counts
                    .sorted { lhs, rhs in
                        let lhsCode = cptByID[lhs.key]?.code ?? String(lhs.key)
                        let rhsCode = cptByID[rhs.key]?.code ?? String(rhs.key)
                        return lhsCode < rhsCode
                    }
                    .map { cptID, count in
                        csvRow(
                            record: record,
                            cpt: cptByID[cptID],
                            cptID: cptID,
                            count: count,
                            profileName: profileNamesByID[record.workProfileIDString ?? ""] ?? "Unknown"
                        )
                    }
            }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    // Column labels for the exported charge file.
    private func csvHeader() -> String {
        let yearColumns = supportedRVUYears.flatMap { year in
            ["Work RVU \(year)", "Total RVU \(year)"]
        }

        return csvLine(["Profile", "Date", "CPT Code", "Description", "Count"] + yearColumns)
    }

    // Converts one saved CPT count into a CSV row.
    private func csvRow(record: DayRecord, cpt: CPTCode?, cptID: Int, count: Int, profileName: String) -> String {
        let yearValues = supportedRVUYears.flatMap { year -> [String] in
            guard let rvu = cpt?.rvu(for: year) else {
                return ["", ""]
            }

            return [
                String(format: "%.2f", rvu),
                String(format: "%.2f", Double(count) * rvu)
            ]
        }

        return csvLine([
            profileName,
            record.dayKey,
            cpt?.code ?? String(cptID),
            cpt?.description ?? "Unknown CPT",
            String(count)
        ] + yearValues)
    }

    // Escapes values using standard CSV double-quote rules.
    private func csvLine(_ values: [String]) -> String {
        values
            .map { value in
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                    return "\"\(escaped)\""
                }
                return escaped
            }
            .joined(separator: ",")
    }

    // File-system-friendly export name based on the selected profile.
    private func csvFilename(for profileName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = profileName
            .map { character -> Character in
                character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
            }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "RVU-\(cleaned.isEmpty ? defaultWorkProfileName : cleaned).csv"
    }

    // Performs the reset chosen in the confirmation alert.
    private func performPendingReset() {
        switch resetScopePendingConfirmation {
        case .activeProfile:
            deleteRecords(activeProfileRecords)
        case .allProfiles:
            deleteRecords(allChargeRecords)
        case nil:
            break
        }

        resetScopePendingConfirmation = nil
    }

    // Deletes charge records while leaving profiles and preferences untouched.
    private func deleteRecords(_ recordsToDelete: [DayRecord]) {
        for record in recordsToDelete {
            modelContext.delete(record)
        }

        try? modelContext.save()
    }

    // Deletes the profile selected in the confirmation alert. Same-date records
    // are merged when moving charges onto the replacement profile.
    private func deletePendingProfile() {
        guard let profile = profilePendingDelete else { return }
        let remainingProfiles = workProfiles.filter { $0.id != profile.id }
        guard !remainingProfiles.isEmpty else {
            profilePendingDelete = nil
            return
        }

        let deletedActiveProfile = profile.id.uuidString == activeWorkProfileID
        let replacementProfile = remainingProfiles[0]

        let recordsToMove = records.filter { $0.workProfileID == profile.id }
        for record in recordsToMove {
            if let replacementRecord = records.first(where: {
                $0.workProfileID == replacementProfile.id && $0.dayKey == record.dayKey
            }) {
                replacementRecord.counts = mergedCounts(replacementRecord.counts, record.counts)
                modelContext.delete(record)
            } else {
                record.workProfileID = replacementProfile.id
            }
        }

        modelContext.delete(profile)

        if deletedActiveProfile {
            activeWorkProfileID = replacementProfile.id.uuidString
            applyActiveProfileSettings()
        }

        try? modelContext.save()
        profilePendingDelete = nil
    }

    // Adds CPT counts together when two profiles have charges on the same date.
    private func mergedCounts(_ first: [Int: Int], _ second: [Int: Int]) -> [Int: Int] {
        second.reduce(into: first) { partialResult, item in
            partialResult[item.key, default: 0] += item.value
        }
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

    // Saves edits from the Profile Defaults section onto the selected profile.
    private func saveCurrentSettingsToActiveProfile() {
        guard let profile = activeProfile else { return }
        profile.providerProfileRaw = selectedProfileRaw
        profile.scheduleModeRaw = scheduleModeRaw
        profile.singleRVUYear = singleRVUYear
        profile.baseRVUYear = baseRVUYear
        profile.comparisonRVUYear = comparisonRVUYear
        try? modelContext.save()
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
                    shiftDisplayedMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    shiftDisplayedMonth(by: 1)
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    handleMonthSwipe(value)
                }
        )
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

    // Moves the calendar by whole months for both arrow taps and swipe gestures.
    private func shiftDisplayedMonth(by offset: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    // Treats horizontal swipes as month changes and ignores mostly vertical drags.
    private func handleMonthSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height

        guard abs(horizontalDistance) > abs(verticalDistance),
              abs(horizontalDistance) > 40 else {
            return
        }

        shiftDisplayedMonth(by: horizontalDistance < 0 ? 1 : -1)
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
    @State private var hasSavedRecordForDate = false
    @State private var showMoveChargesSheet = false
    @State private var moveDestinationDate = Date()
    @State private var moveChargeMode = MoveChargeMode.merge
    @State private var showTransferProfileSheet = false
    @State private var destinationWorkProfileID = ""
    @State private var profileTransferAction = ProfileTransferAction.move
    @State private var profileTransferChargeMode = MoveChargeMode.merge

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

    // String form used in SwiftData predicates for profile/date lookups.
    private var activeWorkProfileIDString: String {
        activeWorkProfile?.id.uuidString ?? activeWorkProfileID
    }

    // Profiles other than the active one, used as transfer destinations.
    private var destinationWorkProfiles: [WorkProfile] {
        workProfiles.filter { $0.id.uuidString != activeWorkProfileIDString }
    }

    // A profile transfer needs saved charges and at least one other profile.
    private var canTransferToAnotherProfile: Bool {
        hasSavedRecordForDate && !destinationWorkProfiles.isEmpty
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

            Button {
                moveDestinationDate = date
                moveChargeMode = .merge
                showMoveChargesSheet = true
            } label: {
                Text("Move Saved Charges to Another Date")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(hasSavedRecordForDate ? Color.orange.opacity(0.18) : Color.gray.opacity(0.12))
                    .foregroundColor(hasSavedRecordForDate ? .primary : .secondary)
                    .cornerRadius(10)
            }
            .disabled(!hasSavedRecordForDate)
            .padding(.horizontal)

            Button {
                prepareProfileTransfer()
            } label: {
                Text("Move or Copy Charges to Another Profile")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(canTransferToAnotherProfile ? Color.purple.opacity(0.16) : Color.gray.opacity(0.12))
                    .foregroundColor(canTransferToAnotherProfile ? .primary : .secondary)
                    .cornerRadius(10)
            }
            .disabled(!canTransferToAnotherProfile)
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
        .sheet(isPresented: $showMoveChargesSheet) {
            NavigationStack {
                moveChargesSheet
            }
        }
        .sheet(isPresented: $showTransferProfileSheet) {
            NavigationStack {
                transferProfileSheet
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

            countStepper(for: cpt)
        }
        .padding(.vertical, 4)
    }

    // Current saved value for a CPT row; blank fields behave the same as zero.
    private func countValue(for cpt: CPTCode) -> Int {
        Int(chargeCounts[cpt.id, default: ""]) ?? 0
    }

    // Stores row counts as strings so the existing save/load path stays unchanged.
    private func setCount(_ count: Int, for cpt: CPTCode) {
        chargeCounts[cpt.id] = count > 0 ? String(count) : ""
        statusMessage = nil
    }

    // Applies one tap from the row stepper without allowing negative charges.
    private func adjustCount(for cpt: CPTCode, by amount: Int) {
        let nextCount = max(0, countValue(for: cpt) + amount)
        setCount(nextCount, for: cpt)
    }

    // Arrow-style charge entry avoids opening the keyboard during routine use.
    @ViewBuilder
    private func countStepper(for cpt: CPTCode) -> some View {
        let count = countValue(for: cpt)

        HStack(spacing: 8) {
            Button {
                adjustCount(for: cpt, by: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundColor(count > 0 ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityLabel("Decrease \(cpt.code) count")

            Text(String(count))
                .font(.body.monospacedDigit())
                .fontWeight(count > 0 ? .semibold : .regular)
                .foregroundColor(count > 0 ? .primary : .secondary)
                .frame(minWidth: 28)
                .accessibilityLabel("\(cpt.code) count")
                .accessibilityValue("\(count)")

            Button {
                adjustCount(for: cpt, by: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(cpt.code) count")
        }
    }

    // Sheet content for choosing where a saved day's charges should move.
    private var moveChargesSheet: some View {
        Form {
            Section("Move Charges") {
                LabeledContent("From", value: dateFormatter.string(from: date))

                DatePicker(
                    "To",
                    selection: $moveDestinationDate,
                    displayedComponents: [.date]
                )

                Picker("If destination has charges", selection: $moveChargeMode) {
                    ForEach(MoveChargeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Move Charges", action: moveChargesToSelectedDate)
                    .disabled(Calendar.current.isDate(moveDestinationDate, inSameDayAs: date))
            } footer: {
                Text(moveChargeMode == .merge
                     ? "Merge adds counts to any charges already saved on the destination date."
                     : "Replace deletes any charges already saved on the destination date before moving these charges.")
            }
        }
        .navigationTitle("Move Charges")
        .toolbar {
            Button("Cancel") {
                showMoveChargesSheet = false
            }
        }
    }

    // Sheet content for moving or copying a saved day between profiles.
    private var transferProfileSheet: some View {
        Form {
            Section("Transfer Charges") {
                LabeledContent("Date", value: dateFormatter.string(from: date))
                LabeledContent("From Profile", value: activeWorkProfile?.name ?? defaultWorkProfileName)

                Picker("To Profile", selection: $destinationWorkProfileID) {
                    ForEach(destinationWorkProfiles) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                }

                Picker("Action", selection: $profileTransferAction) {
                    ForEach(ProfileTransferAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.segmented)

                Picker("If destination has charges", selection: $profileTransferChargeMode) {
                    ForEach(MoveChargeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button(profileTransferAction == .move ? "Move Charges" : "Copy Charges", action: transferChargesToSelectedProfile)
                    .disabled(destinationWorkProfileID.isEmpty)
            } footer: {
                Text(profileTransferChargeMode == .merge
                     ? "Merge adds counts to charges already saved for this date in the destination profile."
                     : "Replace overwrites charges already saved for this date in the destination profile.")
            }
        }
        .navigationTitle("Transfer Profile")
        .toolbar {
            Button("Cancel") {
                showTransferProfileSheet = false
            }
        }
    }

    // Finds one saved charge record for the active profile and requested date.
    private func savedRecord(for recordDate: Date) -> DayRecord? {
        savedRecord(for: recordDate, workProfileIDString: activeWorkProfileIDString)
    }

    // Finds one saved charge record for a specific profile and date.
    private func savedRecord(for recordDate: Date, workProfileIDString: String) -> DayRecord? {
        let key = DayRecord.key(for: recordDate)
        let profileIDString = workProfileIDString
        var descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate {
                $0.dayKey == key && $0.workProfileIDString == profileIDString
            }
        )
        descriptor.fetchLimit = 1

        return try? modelContext.fetch(descriptor).first
    }

    // ## Loads saved charge counts for this profile and date into editable state.
    private func loadForDate() {
        let savedRecord = savedRecord(for: date)
        let stored = savedRecord?.counts ?? [:]

        chargeCounts = Dictionary(uniqueKeysWithValues: cptCodes.map { cpt in
            let count = stored[cpt.id] ?? 0
            return (cpt.id, count == 0 ? "" : String(count))
        })
        extraCodeIDs = Set(stored.keys).subtracting(profileCodes.map(\.id))
        hasSavedRecordForDate = savedRecord != nil
    }

    // ## Persists current profile's day charges and presents the result summary.
    private func saveCharges() {
        let normalized = normalizedChargeCounts()

        do {
            let existing = savedRecord(for: date)

            if let existing {
                if normalized.isEmpty {
                    modelContext.delete(existing)
                } else {
                    existing.date = DayRecord.startOfDay(for: date)
                    existing.counts = normalized
                    existing.workProfileID = activeWorkProfile?.id
                }
            } else if !normalized.isEmpty {
                // Store a separate same-date record for each profile.
                modelContext.insert(DayRecord(date: date, counts: normalized, workProfileID: activeWorkProfile?.id))
            }

            try modelContext.save()
            statusMessage = nil
            hasSavedRecordForDate = !normalized.isEmpty
            buildSummary(from: normalized)
            showSummary = true
        } catch {
            statusMessage = "Unable to save. Please try again."
        }
    }

    // Current text-field values collapsed into positive integer CPT counts.
    private func normalizedChargeCounts() -> [Int: Int] {
        chargeCounts.reduce(into: [Int: Int]()) { partialResult, item in
            let count = Int(item.value) ?? 0
            if count > 0 {
                partialResult[item.key] = count
            }
        }
    }

    // Initializes the profile-transfer sheet with a valid destination and safe defaults.
    private func prepareProfileTransfer() {
        guard let firstDestination = destinationWorkProfiles.first else { return }
        destinationWorkProfileID = firstDestination.id.uuidString
        profileTransferAction = .move
        profileTransferChargeMode = .merge
        showTransferProfileSheet = true
    }

    // Moves or copies this date's saved charges into another profile.
    private func transferChargesToSelectedProfile() {
        guard !destinationWorkProfileID.isEmpty else { return }
        guard let sourceRecord = savedRecord(for: date) else {
            statusMessage = "No saved charges found for this date."
            showTransferProfileSheet = false
            loadForDate()
            return
        }

        let transferredCounts = sourceRecord.counts
        let destinationProfileID = UUID(uuidString: destinationWorkProfileID)

        do {
            if let destinationRecord = savedRecord(for: date, workProfileIDString: destinationWorkProfileID) {
                switch profileTransferChargeMode {
                case .merge:
                    destinationRecord.counts = mergedCounts(destinationRecord.counts, transferredCounts)
                case .replace:
                    destinationRecord.counts = transferredCounts
                }
                destinationRecord.workProfileID = destinationProfileID
            } else {
                modelContext.insert(DayRecord(date: date, counts: transferredCounts, workProfileID: destinationProfileID))
            }

            if profileTransferAction == .move {
                modelContext.delete(sourceRecord)
            }

            try modelContext.save()
            showTransferProfileSheet = false
            statusMessage = profileTransferStatusMessage()
            loadForDate()
        } catch {
            statusMessage = "Unable to transfer charges. Please try again."
        }
    }

    // Short confirmation message after a profile move or copy succeeds.
    private func profileTransferStatusMessage() -> String {
        let destinationName = workProfiles.first { $0.id.uuidString == destinationWorkProfileID }?.name ?? "selected profile"
        switch profileTransferAction {
        case .move:
            return "Moved charges to \(destinationName)."
        case .copy:
            return "Copied charges to \(destinationName)."
        }
    }

    // Moves the saved record for this date to the selected destination date.
    private func moveChargesToSelectedDate() {
        guard !Calendar.current.isDate(moveDestinationDate, inSameDayAs: date) else { return }
        guard let sourceRecord = savedRecord(for: date) else {
            statusMessage = "No saved charges found for this date."
            showMoveChargesSheet = false
            loadForDate()
            return
        }

        let destinationDate = DayRecord.startOfDay(for: moveDestinationDate)
        let destinationKey = DayRecord.key(for: destinationDate)
        let movedCounts = sourceRecord.counts

        do {
            if let destinationRecord = savedRecord(for: destinationDate) {
                switch moveChargeMode {
                case .merge:
                    destinationRecord.counts = mergedCounts(destinationRecord.counts, movedCounts)
                case .replace:
                    destinationRecord.counts = movedCounts
                }
                destinationRecord.date = destinationDate
                destinationRecord.dayKey = destinationKey
                destinationRecord.workProfileID = activeWorkProfile?.id
                modelContext.delete(sourceRecord)
            } else {
                sourceRecord.date = destinationDate
                sourceRecord.dayKey = destinationKey
                sourceRecord.workProfileID = activeWorkProfile?.id
            }

            try modelContext.save()
            showMoveChargesSheet = false
            statusMessage = "Moved charges to \(dateFormatter.string(from: destinationDate))."
            loadForDate()
        } catch {
            statusMessage = "Unable to move charges. Please try again."
        }
    }

    // Adds matching CPT counts when moving into a destination day with saved charges.
    private func mergedCounts(_ first: [Int: Int], _ second: [Int: Int]) -> [Int: Int] {
        second.reduce(into: first) { partialResult, item in
            partialResult[item.key, default: 0] += item.value
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
    let workProfileIDString: String?

    // Year totals are intentionally scoped to the profile selected on the main screen.
    private var activeProfileRecords: [DayRecord] {
        guard let workProfileIDString else { return [] }
        return records.filter { $0.workProfileIDString == workProfileIDString }
    }

    // Navigation title helper that avoids locale punctuation in the year.
    private var plainYearString: String {
        String(year)
    }

    var body: some View {
        let perMonth = monthlyTotals(records: activeProfileRecords, year: year, scheduleYears: scheduleYears)

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
