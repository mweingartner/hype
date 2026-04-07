import SwiftUI

struct PreferencesView: View {
    @AppStorage("ollamaHost") private var ollamaHost = "localhost"
    @AppStorage("ollamaPort") private var ollamaPort = "11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @State private var availableModels: [String] = []
    @State private var isLoading = false
    @State private var connectionStatus = ""

    var body: some View {
        Form {
            Section("Ollama Connection") {
                TextField("Host", text: $ollamaHost)
                TextField("Port", text: $ollamaPort)

                HStack {
                    Button("Test Connection") { testConnection() }
                    if isLoading { ProgressView().scaleEffect(0.7) }
                    Text(connectionStatus)
                        .foregroundColor(connectionStatus.contains("Connected") ? .green : .red)
                        .font(.system(size: 11))
                }
            }

            Section("Model") {
                Picker("Model", selection: $ollamaModel) {
                    if availableModels.isEmpty {
                        Text(ollamaModel).tag(ollamaModel)
                    }
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button("Refresh Models") { fetchModels() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .onAppear { fetchModels() }
    }

    private func testConnection() {
        isLoading = true
        connectionStatus = ""
        Task {
            let urlString = "http://\(ollamaHost):\(ollamaPort)/api/tags"
            guard let url = URL(string: urlString) else {
                connectionStatus = "Invalid URL"
                isLoading = false
                return
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    connectionStatus = "Connected"
                } else {
                    connectionStatus = "Error: unexpected status"
                }
            } catch {
                connectionStatus = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func fetchModels() {
        let urlString = "http://\(ollamaHost):\(ollamaPort)/api/tags"
        guard let url = URL(string: urlString) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    availableModels = models.compactMap { $0["name"] as? String }
                    if !availableModels.isEmpty && !availableModels.contains(ollamaModel) {
                        ollamaModel = availableModels[0]
                    }
                }
            } catch {
                // Silently fail -- models stay empty until user refreshes
            }
        }
    }
}
