import SwiftUI
import WebKit
import UniformTypeIdentifiers
import SwiftLlama

struct ChatMessage: Identifiable {
    let id = UUID()
    let user: Bool
    var text: String
}

struct LocalModel: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class AppState: ObservableObject {
    @Published var tab = 0
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var models: [LocalModel] = []
    @Published var loadedModelName: String?
    @Published var status = "Geen model geladen"
    private var llama: LlamaService?

    func refreshModels() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        models = urls.filter { $0.pathExtension.lowercased() == "gguf" }.map { LocalModel(url: $0) }
    }

    func importModel(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let destination = dir.appendingPathComponent(url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        refreshModels()
    }

    func load(_ model: LocalModel) {
        llama = LlamaService(
            modelUrl: model.url,
            config: .init(batchSize: 128, maxTokenCount: 2048, useGPU: true)
        )
        loadedModelName = model.name
        status = "Model geladen"
    }

    func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        messages.append(.init(user: true, text: q))

        if q.lowercased().contains("open youtube") {
            messages.append(.init(user: false, text: "Ik open YouTube in CleanView."))
            tab = 2
            return
        }

        guard let llama else {
            messages.append(.init(user: false, text: "Laad eerst een GGUF-model bij Instellingen."))
            return
        }

        messages.append(.init(user: false, text: ""))

        Task {
            do {
                let stream = try await llama.streamCompletion(
                    of: [
                        .init(role: .system, content: "Je bent een behulpzame lokale AI-assistent."),
                        .init(role: .user, content: q)
                    ],
                    samplingConfig: .init(temperature: 0.7, seed: 42)
                )

                for try await token in stream {
                    if let i = messages.indices.last {
                        messages[i].text += token
                    }
                }
            } catch {
                if let i = messages.indices.last {
                    messages[i].text = "Fout: \(error.localizedDescription)"
                }
            }
        }
    }
}

@main
struct LocalIntelligenceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $state.tab) {
                HomeView().tabItem { Label("Home", systemImage: "sparkles") }.tag(0)
                ChatView().tabItem { Label("Ask", systemImage: "bubble.left.and.bubble.right.fill") }.tag(1)
                CleanView().tabItem { Label("CleanView", systemImage: "shield.checkered") }.tag(2)
                SettingsView().tabItem { Label("Instellingen", systemImage: "gearshape.fill") }.tag(3)
            }
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .onAppear { state.refreshModels() }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "brain.head.profile.fill").font(.system(size: 64))
                Text("Local Intelligence").font(.largeTitle.bold())
                Text("Lokale AI + CleanView").foregroundStyle(.secondary)
                Button("Vraag lokale AI") { state.tab = 1 }.buttonStyle(.borderedProminent)
                Button("Open CleanView") { state.tab = 2 }.buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.messages) { msg in
                            HStack {
                                if msg.user { Spacer() }
                                Text(msg.text.isEmpty ? "…" : msg.text)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                if !msg.user { Spacer() }
                            }
                        }
                    }.padding()
                }
                HStack {
                    TextField("Vraag iets…", text: $state.input).textFieldStyle(.roundedBorder)
                    Button { state.send() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                }.padding()
            }.navigationTitle("Ask")
        }
    }
}

struct CleanView: View {
    @State private var currentURL = URL(string: "https://m.youtube.com")!
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("YouTube") { currentURL = URL(string: "https://m.youtube.com")! }
                    Button("Twitch") { currentURL = URL(string: "https://m.twitch.tv")! }
                    Button("TikTok") { currentURL = URL(string: "https://www.tiktok.com")! }
                }.buttonStyle(.bordered).padding(8)

                FilteredWebView(url: currentURL)
            }.navigationTitle("CleanView")
        }
    }
}

struct FilteredWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true

        let view = WKWebView(frame: .zero, configuration: config)

        let rules = """
        [
          {"trigger":{"url-filter":".*doubleclick\\\\.net.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*googlesyndication\\\\.com.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*google-analytics\\\\.com.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block-cookies"}}
        ]
        """

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "CleanViewMini",
            encodedContentRuleList: rules
        ) { list, _ in
            if let list { content.add(list) }
            view.load(URLRequest(url: url))
        }

        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var importer = false

    var body: some View {
        NavigationStack {
            List {
                Section("Model") {
                    ForEach(state.models) { model in
                        HStack {
                            Text(model.name)
                            Spacer()
                            Button("Laad") { state.load(model) }
                        }
                    }

                    Button("GGUF-model importeren") { importer = true }
                }

                Section("Status") {
                    Text(state.status)
                    if let name = state.loadedModelName {
                        Text(name).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Instellingen")
            .fileImporter(
                isPresented: $importer,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                do {
                    if let url = try result.get().first {
                        try state.importModel(url)
                    }
                } catch {
                    state.status = error.localizedDescription
                }
            }
        }
    }
}
