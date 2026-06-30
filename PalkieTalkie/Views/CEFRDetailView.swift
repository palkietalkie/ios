import SwiftUI

struct CEFRDetailView: View {
    @Environment(\.backendAPI) private var api
    @State private var level: String = "B1"
    @State private var words: [CEFRWord] = []
    @State private var loadError: String?

    var body: some View {
        VStack {
            Picker("CEFR level", selection: $level) {
                ForEach(["A1", "A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if let loadError {
                Text("Couldn't load words: \(loadError)")
                    .font(.footnote).foregroundStyle(.red).padding(.horizontal).textSelection(.enabled)
            }
            List(words) { word in
                HStack {
                    Text(word.word)
                    Spacer()
                    if word.used {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("CEFR \(level)")
        .task(id: level) {
            // Surface failures instead of `try?`-swallowing them into an empty list (the KG-bug class).
            do {
                words = try await api.getCEFRWords(level: level)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
