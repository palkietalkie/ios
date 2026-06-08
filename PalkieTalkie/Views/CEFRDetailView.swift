import SwiftUI

struct CEFRDetailView: View {
    @Environment(\.backendAPI) private var api
    @State private var level: String = "B1"
    @State private var words: [CEFRWord] = []

    var body: some View {
        VStack {
            Picker("CEFR level", selection: $level) {
                ForEach(["A1", "A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

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
            words = await (try? api.getCEFRWords(level: level)) ?? []
        }
    }
}
