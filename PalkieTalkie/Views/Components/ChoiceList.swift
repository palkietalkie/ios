import SwiftUI

/// Spacious tap-to-select list used by every wizard step (replaces the pushed `MultiLanguagePicker`, so there's no sub-screen to "save and back" out of). Single- vs multi-select is the caller's concern via `isSelected`/`onTap`.
@MainActor
struct ChoiceList: View {
    let options: [String]
    let isSelected: (String) -> Bool
    /// Maps the wire value (English language/accent name) to its localized display. The raw `option` stays the selection key; only the label is localized.
    var display: (String) -> String = { $0 }
    let onTap: (String) -> Void

    /// Long option lists (goals, languages) make a single column scroll off-screen; switch to two columns past this count so they fit without endless vertical scrolling. Short lists (proficiency, speed) stay one column — two would look sparse and the rows would be needlessly narrow.
    private var columns: [GridItem] {
        let count = options.count > 6 ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let selected = isSelected(option)
                    HStack {
                        Text(display(option)).foregroundStyle(.primary)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    // Fill the row's full height before the background so a cell whose label wraps to two lines (e.g. "Norwegian Bokmål") and its single-line neighbor (e.g. "Swedish") render at the same height. In a LazyVGrid the row is as tall as its tallest cell; maxHeight: .infinity makes the shorter cell stretch to match instead of leaving a gap under its background.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5),
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(option) }
                }
            }
            .padding(.bottom, 8)
        }
    }
}
