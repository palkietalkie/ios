import SwiftUI

/// Spacious tap-to-select list used by every wizard step (replaces the pushed `MultiLanguagePicker`, so there's no sub-screen to "save and back" out of). Single- vs multi-select is the caller's concern via `isSelected`/`onTap`.
@MainActor
struct ChoiceList: View {
    let options: [String]
    let isSelected: (String) -> Bool
    /// Maps the wire value (English language/accent name) to its localized display. The raw `option` stays the selection key; only the label is localized.
    var display: (String) -> String = { $0 }
    let onTap: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
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
