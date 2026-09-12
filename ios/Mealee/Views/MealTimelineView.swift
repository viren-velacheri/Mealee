import SwiftUI

// The day read downward: every confirmed meal, when it was eaten, what was in it, and
// which stats it moved. The spine makes it a timeline rather than a list of cards.
struct MealTimelineView: View {
    let entries: [TimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today").font(TypeScale.heading).foregroundStyle(Palette.ink)
            if entries.isEmpty {
                Notice(kind: .guidance, text: "Nothing logged yet. Meals and drinks land here with what they changed.")
            } else {
                ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                    TimelineRow(entry: entry, isLast: index == entries.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            spine
            VStack(alignment: .leading, spacing: 6) {
                // The clock leads the row: the day reads as a sequence of times, and it
                // can no longer be clipped by a fixed column at large text sizes.
                Text(clockTime).font(TypeScale.label).foregroundStyle(Palette.ink)
                Text(entry.label).font(TypeScale.body).foregroundStyle(Palette.ink)
                if !entry.nutrients.summary.isEmpty {
                    Text(entry.nutrients.summary.map { "\($0.1) \($0.0)" }.joined(separator: " · "))
                        .font(TypeScale.caption).foregroundStyle(Palette.muted)
                }
                if !entry.delta.risen.isEmpty {
                    // A meal can move all six stats, so the chips scroll rather than squeeze.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(entry.delta.risen, id: \.0) { name, amount in
                                Text("\(name) +\(amount, specifier: "%.1f")")
                                    .font(TypeScale.label).foregroundStyle(Palette.ink)
                                    .fixedSize()
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Palette.leaf.opacity(0.4), in: Capsule())
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 8)
    }

    private var spine: some View {
        VStack(spacing: 0) {
            Circle().fill(entry.isDrink ? Palette.slate : Palette.leaf).frame(width: 10, height: 10)
            if !isLast {
                Rectangle().fill(Palette.mint).frame(width: 2).frame(maxHeight: .infinity)
            }
        }
        .frame(width: 10)
    }

    // The server sends microseconds on drinks and none on meals, and ISO8601DateFormatter
    // parses only what it is told to expect, so try both.
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    private var clockTime: String {
        let raw = entry.takenAt
        guard let date = Self.withFraction.date(from: raw) ?? Self.plain.date(from: raw) else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
