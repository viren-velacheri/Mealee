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
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
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
            VStack(spacing: 0) {
                Text(clockTime).font(TypeScale.caption).foregroundStyle(Palette.muted)
                    .frame(width: 52, alignment: .trailing)
                Spacer(minLength: 0)
            }
            spine
            VStack(alignment: .leading, spacing: 6) {
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

    private var clockTime: String {
        guard let date = ISO8601DateFormatter().date(from: entry.takenAt) else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
