//
//  ResultView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct CPTSummary: Identifiable {
    let id: Int
    let code: String
    let count: Int
    let totalsByYear: [Int: Double]
    let warning: String?
}

struct ResultView: View {
    @Environment(\.colorScheme) private var colorScheme

    let scheduleYears: [Int]
    let totalsByYear: [Int: Double]
    let cptSummaries: [CPTSummary]
    var onReturnToCalendar: (() -> Void)? = nil

    private var firstYear: Int? { scheduleYears.first }
    private var secondYear: Int? { scheduleYears.dropFirst().first }
    private var totalBlueCardTint: Color { colorScheme == .dark ? Color.blue.opacity(0.24) : Color.blue.opacity(0.12) }
    private var totalGreenCardTint: Color { colorScheme == .dark ? Color.green.opacity(0.24) : Color.green.opacity(0.12) }
    private var cptBlueChipBackground: Color { colorScheme == .dark ? Color.blue.opacity(0.30) : Color.blue.opacity(0.14) }
    private var cptGreenChipBackground: Color { colorScheme == .dark ? Color.green.opacity(0.30) : Color.green.opacity(0.14) }

    private var changeText: String? {
        guard
            let firstYear,
            let secondYear,
            let base = totalsByYear[firstYear],
            base > 0,
            let comparison = totalsByYear[secondYear]
        else {
            return nil
        }

        let pct = ((comparison - base) / base) * 100
        return String(format: "%+.1f%% vs %d", pct, firstYear)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Total RVUs")
                    .font(.title)
                    .fontWeight(.semibold)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    ForEach(Array(scheduleYears.enumerated()), id: \.element) { index, year in
                        totalCard(
                            title: "\(year) Schedule",
                            value: totalsByYear[year, default: 0],
                            tint: index == 0 ? totalBlueCardTint : totalGreenCardTint,
                            emphasized: emphasizedYear == year,
                            badge: year == secondYear ? changeText : nil
                        )
                    }
                }

                VStack(spacing: 10) {
                    Text("CPT Summary")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    headerRow

                    Divider()

                    if cptSummaries.isEmpty {
                        Text("No CPT entries with charges.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(cptSummaries.enumerated()), id: \.element.id) { index, summary in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(summary.code) x\(summary.count)")
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    ForEach(Array(scheduleYears.enumerated()), id: \.element) { yearIndex, year in
                                        Text(valueText(summary.totalsByYear[year]))
                                            .font(.body.monospacedDigit())
                                            .frame(width: 96, alignment: .trailing)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 6)
                                            .background(yearIndex == 0 ? cptBlueChipBackground : cptGreenChipBackground)
                                            .cornerRadius(6)
                                    }
                                }

                                if let warning = summary.warning {
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(index.isMultiple(of: 2) ? Color.white.opacity(0.45) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(.sRGB, white: 0.42, opacity: 1.0), Color(.sRGB, white: 0.20, opacity: 1.0)]
                            : [Color.white, Color(.sRGB, white: 0.94, opacity: 1.0)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)

                if let onReturnToCalendar {
                    Button(action: onReturnToCalendar) {
                        Text("Return to Calendar")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Results")
    }

    private var emphasizedYear: Int? {
        guard scheduleYears.count == 2 else { return nil }
        return scheduleYears.max { totalsByYear[$0, default: 0] < totalsByYear[$1, default: 0] }
    }

    private var headerRow: some View {
        HStack {
            Text("CPT")
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(scheduleYears.enumerated()), id: \.element) { index, year in
                Text(String(year))
                    .frame(width: 96, alignment: .trailing)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(index == 0 ? cptBlueChipBackground : cptGreenChipBackground)
                    .cornerRadius(6)
            }
        }
        .font(.subheadline.bold())
        .padding(.horizontal, 6)
    }

    private func valueText(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.2f", value)
    }

    // ## Renders one schedule total card with optional emphasis and change badge.
    private func totalCard(title: String, value: Double, tint: Color, emphasized: Bool, badge: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)

            Text("\(value, specifier: "%.2f")")
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)

            if let badge {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(tint)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(emphasized ? Color.primary.opacity(0.35) : Color.gray.opacity(0.12), lineWidth: emphasized ? 2 : 1)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
