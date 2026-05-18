//
//  SwiftLMApp.swift
//  SwiftLM
//
//  Created by Johan Sellström on 2026-04-02.
//
import AppKit
import Combine
import ControlPlane
import Contracts
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case models
    case playground
    case activity
    case benchmarks
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        case .playground: return "Playground"
        case .activity: return "Activity"
        case .benchmarks: return "Benchmarks"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .models: return "shippingbox.fill"
        case .playground: return "bubble.left.and.text.bubble.right.fill"
        case .activity: return "gauge.with.dots.needle.50percent"
        case .benchmarks: return "speedometer"
        case .logs: return "doc.text.magnifyingglass"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum ModelLibraryFormatFilter: String, CaseIterable, Identifiable {
    case all
    case mlx
    case gguf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .mlx:
            return "MLX"
        case .gguf:
            return "GGUF"
        }
    }

    func matches(_ result: ModelSearchResult) -> Bool {
        switch self {
        case .all:
            return true
        case .mlx:
            return result.artifactFormats.contains(.mlx)
        case .gguf:
            return result.artifactFormats.contains(.gguf)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var overview: AppOverview?
    @Published var currentConversation: ConversationRecord?
    @Published var draftMessage = ""
    @Published var selectedModelID: String?
    @Published var modelSearchQuery = ""
    @Published var modelSearchFormatFilter: ModelLibraryFormatFilter = .all
    @Published var modelSearchResults: [ModelSearchResult] = []
    @Published var presentedModelCardResult: ModelSearchResult?
    @Published var presentedModelCard: ModelCatalogCard?
    @Published var modelCardLoading = false
    @Published var modelCardError: String?
    @Published var importSource = "Qwen/Qwen2.5-7B-Instruct-4bit"
    @Published var importDisplayName = "Qwen 2.5 7B Instruct 4bit"
    @Published var statusLine = "Booting local control plane"
    @Published var loading = false
    @Published var searchingModels = false
    @Published var benchmarkScenario: BenchmarkScenario = .chatLatency
    @Published var launchResult: EngineInstanceRef?

    private var host: ControlPlaneHost?
    private var client = ControlPlaneClient()
    private var bootstrapTask: Task<Void, Never>?

    var importedModels: [ModelRecord] {
        overview?.models ?? []
    }

    var activeInstances: [InstanceActivity] {
        overview?.activity.activeInstances ?? []
    }

    var filteredModelSearchResults: [ModelSearchResult] {
        modelSearchResults.filter { modelSearchFormatFilter.matches($0) }
    }

    var trayServerStatusText: String {
        guard let overview else {
            return "SwiftLM Control Plane: Starting"
        }
        return overview.health.status == "ok"
            ? "SwiftLM Control Plane: Running"
            : "SwiftLM Control Plane: Not Running"
    }

    var trayImportedModelCountText: String {
        let count = importedModels.count
        return "\(count) Model\(count == 1 ? "" : "s") Imported"
    }

    var trayLoadedModelCountText: String {
        let count = activeInstances.count
        return "\(count) Model\(count == 1 ? "" : "s") Loaded"
    }

    var trayLoadedModelNames: [String] {
        activeInstances.map { instance in
            importedModels.first(where: { $0.id == instance.modelId })?.ref.displayName ?? instance.modelId
        }
    }

    var trayStatusSymbol: String {
        if loading {
            return "ellipsis.circle"
        }
        return activeInstances.isEmpty ? "bolt.horizontal.circle" : "bolt.horizontal.circle.fill"
    }

    func ensureBootstrapped() {
        guard bootstrapTask == nil else { return }
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    func bootstrap() async {
        loading = true
        defer { loading = false }
        log("UI bootstrap started.")
        do {
            let reuseDecider = EmbeddedControlPlaneReuseDecider()
            if await reuseDecider.initialMode() == .existing {
                self.host = nil
                self.client = ControlPlaneClient()
                statusLine = "Connected to existing control plane at http://127.0.0.1:8400"
                log("Connected to an existing control plane at http://127.0.0.1:8400.")
            } else {
                log("Attempting embedded control plane bootstrap.")
                let host = try await ControlPlaneHost.bootstrap()
                log("Embedded control plane bootstrap completed. Attempting to start HTTP server.")
                do {
                    try await host.start()
                    self.host = host
                    self.client = ControlPlaneClient(apiKey: host.secrets.plaintextKey)
                    statusLine = "Embedded control plane running at http://127.0.0.1:8400"
                    log("Embedded control plane started successfully. apiKeyPreview=\(host.secrets.preview)")
                } catch {
                    if await reuseDecider.recoveryMode(afterStartError: error) == .existing {
                        self.host = nil
                        self.client = ControlPlaneClient()
                        statusLine = "Connected to existing control plane at http://127.0.0.1:8400"
                        log("Connected to an existing control plane after detecting a port-ownership race on http://127.0.0.1:8400.")
                    } else {
                        throw error
                    }
                }
            }
            log("Refreshing overview after bootstrap.")
            do {
                try await refresh()
                log("Overview refresh completed.")
            } catch {
                log("Overview refresh failed during bootstrap. \(describe(error))")
                throw error
            }
        } catch {
            log("UI bootstrap failed. \(describe(error))")
            statusLine = "Failed to bootstrap: \(error.localizedDescription)"
        }
    }

    func refresh() async throws {
        overview = try await client.fetchOverview()
        if selectedModelID == nil {
            selectedModelID = overview?.models.first?.id
        }
        if currentConversation == nil, let existing = overview?.conversations.first {
            currentConversation = existing
        }
    }

    func importModel() async {
        loading = true
        defer { loading = false }
        do {
            let record = try await importModel(
                ImportModelRequest(
                    displayName: importDisplayName.isEmpty ? nil : importDisplayName,
                    sourceKind: importSource.hasPrefix("/") ? .local : .huggingFace,
                    sourceRef: importSource
                )
            )
            selectedModelID = record.id
            statusLine = "Imported \(record.ref.displayName)"
            try await refresh()
        } catch {
            statusLine = "Import failed: \(error.localizedDescription)"
        }
    }

    func searchModelCatalog() async {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            modelSearchResults = []
            statusLine = "Enter a model name to search Hugging Face."
            return
        }

        searchingModels = true
        defer { searchingModels = false }

        do {
            let response = try await client.searchModels(query: query, limit: 30)
            modelSearchResults = response.results
            statusLine = searchStatusLine(query: response.query, totalCount: response.results.count)
        } catch {
            modelSearchResults = []
            statusLine = "Search failed: \(error.localizedDescription)"
        }
    }

    func useSearchResult(_ result: ModelSearchResult) {
        importSource = result.id
        importDisplayName = result.displayName.replacingOccurrences(of: "-", with: " ")
        statusLine = "Prepared \(result.id) for import."
    }

    func importSearchResult(_ result: ModelSearchResult) async {
        loading = true
        defer { loading = false }
        do {
            let record = try await importModel(
                ImportModelRequest(
                    displayName: result.displayName,
                    sourceKind: .huggingFace,
                    sourceRef: result.id
                )
            )
            importSource = result.id
            importDisplayName = result.displayName
            selectedModelID = record.id
            statusLine = "Imported \(record.ref.displayName)"
            try await refresh()
        } catch {
            statusLine = "Import failed: \(error.localizedDescription)"
        }
    }

    func presentModelCard(for result: ModelSearchResult) async {
        presentedModelCardResult = result
        presentedModelCard = nil
        modelCardError = nil
        modelCardLoading = true

        do {
            let card = try await client.fetchModelCard(id: result.id)
            guard presentedModelCardResult?.id == result.id else {
                return
            }
            presentedModelCard = card
            statusLine = "Loaded model card for \(result.displayName)"
        } catch {
            guard presentedModelCardResult?.id == result.id else {
                return
            }
            modelCardError = error.localizedDescription
            statusLine = "Model card failed: \(error.localizedDescription)"
        }

        if presentedModelCardResult?.id == result.id {
            modelCardLoading = false
        }
    }

    func dismissModelCard() {
        presentedModelCardResult = nil
        presentedModelCard = nil
        modelCardError = nil
        modelCardLoading = false
    }

    func inspect(_ model: ModelRecord) async {
        do {
            _ = try await client.inspectModel(id: model.id)
            statusLine = "Inspected \(model.ref.displayName)"
            try await refresh()
        } catch {
            statusLine = "Inspect failed: \(error.localizedDescription)"
        }
    }

    func validate(_ model: ModelRecord) async {
        do {
            let report = try await client.validateModel(id: model.id)
            statusLine = "\(model.ref.displayName) validated on \(report.backendId) with \(report.riskTier.rawValue) risk"
            try await refresh()
        } catch {
            statusLine = "Validation failed: \(error.localizedDescription)"
        }
    }

    func warm(_ model: ModelRecord) async {
        do {
            let instance = try await client.launch(
                LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 512)
            )
            launchResult = instance
            statusLine = "Launched \(model.ref.displayName) on \(instance.backendId)"
            try await refresh()
        } catch {
            statusLine = "Launch failed: \(error.localizedDescription)"
        }
    }

    func sendMessage() async {
        guard let selectedModelID, draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        loading = true
        defer { loading = false }

        do {
            let conversationID: String
            if let currentConversation {
                conversationID = currentConversation.id
            } else {
                let conversation = try await client.createConversation(title: "Playground", modelId: selectedModelID)
                currentConversation = conversation
                conversationID = conversation.id
            }

            let updated = try await client.sendMessage(conversationID: conversationID, content: draftMessage)
            currentConversation = updated
            draftMessage = ""
            statusLine = "Playground updated"
            try await refresh()
        } catch {
            statusLine = "Chat failed: \(error.localizedDescription)"
        }
    }

    func runBenchmark() async {
        guard let selectedModelID else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await client.runBenchmark(BenchmarkRequest(modelId: selectedModelID, scenario: benchmarkScenario))
            statusLine = "Benchmark finished: \(Int(result.tokS)) tok/s"
            try await refresh()
        } catch {
            statusLine = "Benchmark failed: \(error.localizedDescription)"
        }
    }

    func installBackend(_ backend: BackendDetection) async {
        loading = true
        defer { loading = false }
        do {
            let updated = try await client.installBackend(id: backend.id)
            statusLine = "Installed \(updated.kind.rawValue)"
            try await refresh()
        } catch {
            statusLine = "Runtime install failed: \(error.localizedDescription)"
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func startPreferredModel() async {
        guard let preferred = importedModels.first(where: { $0.id == selectedModelID }) ?? importedModels.first else {
            statusLine = "Import a model before starting one from the tray."
            return
        }
        selectedModelID = preferred.id
        await warm(preferred)
    }

    func loadModelFromTray(_ model: ModelRecord) async {
        selectedModelID = model.id
        await warm(model)
    }

    func unloadAllModels() async {
        guard activeInstances.isEmpty == false else {
            statusLine = "No running models to unload."
            return
        }

        loading = true
        defer { loading = false }

        do {
            for instance in activeInstances {
                _ = try await client.stopEngine(id: instance.instanceId)
            }
            launchResult = nil
            statusLine = "Stopped all running models"
            try await refresh()
        } catch {
            statusLine = "Failed to unload models: \(error.localizedDescription)"
        }
    }

    private func log(_ message: String) {
        print("[SwiftLM.UI][\(Time.nowISO8601())] \(message)")
    }

    private func importModel(_ request: ImportModelRequest) async throws -> ModelRecord {
        try await client.importModel(request)
    }

    private func searchStatusLine(query: String, totalCount: Int) -> String {
        guard totalCount > 0 else {
            return "No Hugging Face models found for \(query)."
        }

        let filteredCount = filteredModelSearchResults.count
        switch modelSearchFormatFilter {
        case .all:
            return "Found \(totalCount) Hugging Face models for \(query)."
        case .mlx, .gguf:
            return "Showing \(filteredCount) \(modelSearchFormatFilter.title) matches from \(totalCount) Hugging Face results for \(query)."
        }
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "type=\(String(describing: type(of: error)))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]
        if let apiError = error as? APIErrorEnvelope {
            parts.append("apiCode=\(apiError.error.code)")
            parts.append("apiMessage=\(apiError.error.message)")
            if apiError.error.details.isEmpty == false {
                let details = apiError.error.details
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",")
                parts.append("apiDetails=\(details)")
            }
        }
        if let reason = nsError.localizedFailureReason, reason.isEmpty == false {
            parts.append("reason=\(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion, suggestion.isEmpty == false {
            parts.append("suggestion=\(suggestion)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlyingDomain=\(underlying.domain)")
            parts.append("underlyingCode=\(underlying.code)")
            parts.append("underlyingDescription=\(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }
}

public struct SwiftLMApplicationScene: Scene {
    @StateObject private var model = AppModel()
    private let title: String
    private let mainWindowID: String
    private let minimumWindowSize: CGSize

    public init(
        title: String = "SwiftLM",
        mainWindowID: String = "main",
        minimumWindowSize: CGSize = CGSize(width: 1180, height: 760)
    ) {
        self.title = title
        self.mainWindowID = mainWindowID
        self.minimumWindowSize = minimumWindowSize
    }

    public var body: some Scene {
        WindowGroup(title, id: mainWindowID) {
            RootView()
                .environmentObject(model)
                .task {
                    model.ensureBootstrapped()
                }
                .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            TrayPanelView(mainWindowID: mainWindowID)
                .environmentObject(model)
                .task {
                    model.ensureBootstrapped()
                }
        } label: {
            TrayStatusItem()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                LinearGradient(
                    colors: contentBackgroundColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    Group {
                        switch model.selectedSection {
                        case .overview:
                            OverviewView()
                        case .models:
                            ModelsView()
                        case .playground:
                            PlaygroundView()
                        case .activity:
                            ActivityView()
                        case .benchmarks:
                            BenchmarksView()
                        case .logs:
                            LogsView()
                        case .settings:
                            SettingsView()
                        }
                    }
                    .padding(28)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { try? await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var sidebar: some View {
        List(AppSection.allCases) { section in
            Button {
                model.selectedSection = section
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: section.symbol)
                        .frame(width: 18)
                    Text(section.title)
                }
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(model.selectedSection == section ? Color.primary : Color.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(model.selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar-\(section.rawValue)")
        }
        .listStyle(.sidebar)
        .navigationTitle("SwiftLM")
        .safeAreaInset(edge: .bottom) {
            Text(model.statusLine)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let overview = model.overview {
            VStack(alignment: .leading, spacing: 24) {
                header("Control Plane", subtitle: "Apple-Silicon-first orchestration for local LLM serving", colorScheme: colorScheme)
                    .accessibilityIdentifier("section-overview")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                    StatCard(title: "Health", value: overview.health.status.uppercased(), detail: "\(overview.health.activeEngineCount) active engines")
                    StatCard(title: "Models", value: "\(overview.models.count)", detail: "\(overview.health.readyModelCount) ready")
                    StatCard(title: "Memory", value: ByteCountFormatter.string(fromByteCount: overview.activity.estimatedFreeBytes, countStyle: .memory), detail: "\(overview.activity.memoryPressure.rawValue.capitalized) pressure")
                    StatCard(title: "Backends", value: "\(overview.backends.count)", detail: overview.backends.map(\.kind.rawValue).joined(separator: ", "))
                    StatCard(title: "Benchmarks", value: "\(overview.benchmarks.count)", detail: "Historical runs")
                    StatCard(title: "Developer API", value: overview.developerAPI.baseURL, detail: overview.developerAPI.currentKeyPreview ?? "No preview")
                }

                card(colorScheme: colorScheme) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hardware")
                            .font(.title3.weight(.semibold))
                            .fontDesign(.rounded)
                        Text(overview.hardware.chipFamily)
                            .font(.system(.title2, design: .serif, weight: .bold))
                        HStack {
                            MetricPill(label: "Unified Memory", value: ByteCountFormatter.string(fromByteCount: overview.hardware.totalMemoryBytes, countStyle: .memory))
                            MetricPill(label: "GPU Cores", value: "\(overview.hardware.gpuCores)")
                            MetricPill(label: "Free Disk", value: ByteCountFormatter.string(fromByteCount: overview.hardware.freeDiskBytes, countStyle: .file))
                        }
                    }
                }
            }
        } else {
            ProgressView("Loading SwiftLM overview…")
        }
    }
}

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Model Library", subtitle: "Import local folders or Hugging Face refs, inspect them, then validate launch profiles", colorScheme: colorScheme)
                .accessibilityIdentifier("section-models")
            card(colorScheme: colorScheme) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Search Hugging Face")
                                .font(.caption.weight(.semibold))
                            TextField("Qwen, Llama, Gemma…", text: $model.modelSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    Task { await model.searchModelCatalog() }
                                }
                        }
                        Button("Search") {
                            Task { await model.searchModelCatalog() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.searchingModels)
                    }

                    Picker("Format", selection: $model.modelSearchFormatFilter) {
                        ForEach(ModelLibraryFormatFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.searchingModels {
                        ProgressView("Searching Hugging Face…")
                    } else if model.modelSearchResults.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Showing \(model.filteredModelSearchResults.count) of \(model.modelSearchResults.count) results")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if model.filteredModelSearchResults.isEmpty {
                                Text("No \(model.modelSearchFormatFilter.title) results in this search. Try a broader query or switch formats.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(model.filteredModelSearchResults) { result in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.displayName)
                                                .font(.headline)
                                            Text(result.id)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                        Spacer()
                                        Button("Model Card") {
                                            Task { await model.presentModelCard(for: result) }
                                        }
                                        .buttonStyle(.bordered)
                                        Button("Use Ref") {
                                            model.useSearchResult(result)
                                        }
                                        .buttonStyle(.bordered)
                                        Button("Import") {
                                            Task { await model.importSearchResult(result) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(model.loading)
                                    }

                                    HStack {
                                        if let pipelineTag = result.pipelineTag {
                                            MetricPill(label: "Task", value: pipelineTag)
                                        }
                                        if let libraryName = result.libraryName {
                                            MetricPill(label: "Library", value: libraryName)
                                        }
                                        ForEach(result.artifactFormats, id: \.self) { format in
                                            MetricPill(label: "Format", value: format.title)
                                        }
                                        if let downloads = result.downloads {
                                            MetricPill(label: "Downloads", value: compactHubMetric(downloads))
                                        }
                                        if let likes = result.likes {
                                            MetricPill(label: "Likes", value: compactHubMetric(likes))
                                        }
                                    }

                                    if result.tags.isEmpty == false {
                                        Text(result.tags.prefix(6).joined(separator: "  "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(groupPanelFill(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    } else {
                    Text("Search the Hugging Face Hub to find a model, then import it directly or copy its repo id into the manual import form below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            card(colorScheme: colorScheme) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.caption.weight(.semibold))
                        TextField("Qwen 2.5 7B Instruct 4bit", text: $model.importDisplayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Ref")
                            .font(.caption.weight(.semibold))
                        TextField("HF repo or local path", text: $model.importSource)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Import") {
                        Task { await model.importModel() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let models = model.overview?.models, models.isEmpty == false {
                ForEach(models) { record in
                    card(colorScheme: colorScheme) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.ref.displayName)
                                        .font(.title3.weight(.bold))
                                        .fontDesign(.rounded)
                                    Text(record.ref.sourceRef)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.status.rawValue.capitalized)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(record.status == .ready ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            HStack {
                                MetricPill(label: "Architecture", value: record.ref.architecture ?? "Unknown")
                                MetricPill(label: "Quant", value: record.ref.quantization ?? "Auto")
                                MetricPill(label: "Context", value: "\(record.defaultContextWindow ?? 8192)")
                                MetricPill(label: "Risk", value: record.capabilities.riskTier.rawValue.capitalized)
                            }

                            if record.capabilities.warnings.isEmpty == false {
                                Text(record.capabilities.warnings.joined(separator: "  "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button("Inspect") { Task { await model.inspect(record) } }
                                Button("Validate") { Task { await model.validate(record) } }
                                Button("Warm") { Task { await model.warm(record) } }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                card(colorScheme: colorScheme) {
                    Text("No models imported yet. Start with a Hugging Face repo id or a local model directory.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $model.presentedModelCardResult, onDismiss: {
            model.dismissModelCard()
        }) { result in
            ModelCardSheet(result: result)
                .environmentObject(model)
        }
    }
}

struct ModelCardSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let result: ModelSearchResult

    var body: some View {
        ZStack {
            LinearGradient(
                colors: contentBackgroundColors(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(result.displayName, subtitle: result.id, colorScheme: colorScheme)

                    card(colorScheme: colorScheme) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Inspect the full Hugging Face card before importing.")
                                    .foregroundStyle(secondaryTextColor(for: colorScheme))
                                HStack {
                                    if let card = model.presentedModelCard {
                                        if let url = URL(string: card.repositoryURL) {
                                            Link("Open on Hugging Face", destination: url)
                                        }
                                    } else if let fallbackURL = huggingFaceRepositoryURL(for: result.id) {
                                        Link("Open on Hugging Face", destination: fallbackURL)
                                    }
                                }
                            }
                            Spacer()
                            HStack {
                                Button("Use Ref") {
                                    model.useSearchResult(result)
                                }
                                .buttonStyle(.bordered)
                                Button("Import") {
                                    Task { await model.importSearchResult(result) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.loading)
                            }
                        }
                    }

                    if model.modelCardLoading {
                        card(colorScheme: colorScheme) {
                            ProgressView("Loading model card…")
                        }
                    } else if let error = model.modelCardError {
                        card(colorScheme: colorScheme) {
                            Text(error)
                                .foregroundStyle(.secondary)
                        }
                    } else if let modelCard = model.presentedModelCard {
                        card(colorScheme: colorScheme) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Snapshot")
                                    .font(.title3.weight(.semibold))
                                    .fontDesign(.rounded)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                                    if let task = modelCard.pipelineTag {
                                        MetricPill(label: "Task", value: task)
                                    }
                                    if let library = modelCard.libraryName {
                                        MetricPill(label: "Library", value: library)
                                    }
                                    if let downloads = modelCard.downloads {
                                        MetricPill(label: "Downloads", value: compactHubMetric(downloads))
                                    }
                                    if let likes = modelCard.likes {
                                        MetricPill(label: "Likes", value: compactHubMetric(likes))
                                    }
                                    if let license = modelCard.license {
                                        MetricPill(label: "License", value: license)
                                    }
                                    if let baseModel = modelCard.baseModel {
                                        MetricPill(label: "Base Model", value: baseModel)
                                    }
                                    if let updated = modelCard.lastModified {
                                        MetricPill(label: "Updated", value: displayHubDate(updated))
                                    }
                                    if let createdAt = modelCard.createdAt {
                                        MetricPill(label: "Created", value: displayHubDate(createdAt))
                                    }
                                    ForEach(modelCard.artifactFormats, id: \.self) { format in
                                        MetricPill(label: "Format", value: format.title)
                                    }
                                }

                                if modelCard.languages.isEmpty == false {
                                    Text("Languages: \(modelCard.languages.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if modelCard.tags.isEmpty == false {
                                    Text(modelCard.tags.prefix(28).joined(separator: "  "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if modelCard.siblingFiles.isEmpty == false {
                            card(colorScheme: colorScheme) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Files")
                                        .font(.title3.weight(.semibold))
                                        .fontDesign(.rounded)
                                    Text(modelCard.siblingFiles.prefix(24).joined(separator: "\n"))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        card(colorScheme: colorScheme) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Model Card")
                                    .font(.title3.weight(.semibold))
                                    .fontDesign(.rounded)
                                if let readme = modelCard.readme, readme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                    Text(readme)
                                        .font(.system(.body, design: .rounded))
                                        .textSelection(.enabled)
                                } else {
                                    Text("This repository does not expose a README.md model card.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 940, minHeight: 760)
    }
}

struct PlaygroundView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Playground", subtitle: "Route prompts through the control plane and inspect how the app surfaces normalized chat behavior", colorScheme: colorScheme)
                .accessibilityIdentifier("section-playground")
            card(colorScheme: colorScheme) {
                HStack {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                    Picker("Model", selection: $model.selectedModelID) {
                        Text("Select").tag(Optional<String>.none)
                        ForEach(model.overview?.models ?? []) { record in
                            Text(record.ref.displayName).tag(Optional(record.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    if let launch = model.launchResult {
                        Text("Last launch: \(launch.backendId) @ \(launch.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            card(colorScheme: colorScheme) {
                VStack(alignment: .leading, spacing: 14) {
                    if let conversation = model.currentConversation, conversation.messages.isEmpty == false {
                        ForEach(conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(message.role == "assistant" ? Color.green : Color.brown)
                                Text(message.content)
                                    .textSelection(.enabled)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == "assistant" ? assistantBubbleFill(for: colorScheme) : userBubbleFill(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    } else {
                        Text("No conversation yet. Import a model, select it, and send a prompt.")
                            .foregroundStyle(.secondary)
                    }

                    TextField("Ask the local control plane for a routed response", text: $model.draftMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Send") {
                            Task { await model.sendMessage() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Activity", subtitle: "Track queue depth, warm instances, and unified-memory pressure", colorScheme: colorScheme)
                .accessibilityIdentifier("section-activity")
            if let activity = model.overview?.activity {
                card(colorScheme: colorScheme) {
                    HStack {
                        MetricPill(label: "Free Memory", value: ByteCountFormatter.string(fromByteCount: activity.estimatedFreeBytes, countStyle: .memory))
                        MetricPill(label: "Pressure", value: activity.memoryPressure.rawValue.capitalized)
                        MetricPill(label: "Instances", value: "\(activity.activeInstances.count)")
                    }
                }

                if activity.activeInstances.isEmpty {
                    card(colorScheme: colorScheme) {
                        Text("No active engine instances. Use Model Library -> Warm to launch one.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(activity.activeInstances, id: \.instanceId) { instance in
                        card(colorScheme: colorScheme) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(instance.modelId)
                                        .font(.headline)
                                    Text(instance.backendId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                MetricPill(label: "Tok/s", value: instance.outputTokPerSecP50.map { String(format: "%.1f", $0) } ?? "n/a")
                                MetricPill(label: "TTFT", value: instance.ttftMsP50.map { "\(Int($0)) ms" } ?? "n/a")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BenchmarksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Benchmarks", subtitle: "Run reproducible launch-profile scenarios and keep a local history", colorScheme: colorScheme)
                .accessibilityIdentifier("section-benchmarks")
            card(colorScheme: colorScheme) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scenario")
                            .font(.caption.weight(.semibold))
                        Picker("Scenario", selection: $model.benchmarkScenario) {
                            ForEach(BenchmarkScenario.allCases) { scenario in
                                Text(scenario.title).tag(scenario)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(model.benchmarkScenario.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run") {
                        Task { await model.runBenchmark() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            ForEach(model.overview?.benchmarks ?? []) { benchmark in
                card(colorScheme: colorScheme) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(benchmarkScenarioTitle(benchmark.scenario))
                                .font(.headline)
                            Text(benchmark.modelId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        MetricPill(label: "TTFT", value: "\(Int(benchmark.ttftMs)) ms")
                        MetricPill(label: "Tok/s", value: String(format: "%.1f", benchmark.tokS))
                        MetricPill(label: "Latency", value: "\(Int(benchmark.totalLatencyMs)) ms")
                    }
                }
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Logs", subtitle: "Bootstrap, routing, and engine lifecycle diagnostics", colorScheme: colorScheme)
                .accessibilityIdentifier("section-logs")
            ForEach(model.overview?.logs ?? []) { entry in
                card(colorScheme: colorScheme) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.category.uppercased())
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text(entry.createdAt)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.body)
                        if entry.metadata.isEmpty == false {
                            Text(entry.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Settings", subtitle: "Local API posture, backend defaults, and managed runtime installation", colorScheme: colorScheme)
                .accessibilityIdentifier("section-settings")
            if let overview = model.overview {
                card(colorScheme: colorScheme) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Developer API")
                            .font(.title3.weight(.bold))
                            .fontDesign(.rounded)
                        MetricPill(label: "Base URL", value: overview.developerAPI.baseURL)
                        MetricPill(label: "API Key", value: overview.developerAPI.currentKeyPreview ?? "Unavailable")
                        Text("External `/v1/*` routes require the bootstrap key. Internal app routes use `/app/v1/*` on the same localhost control plane.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                card(colorScheme: colorScheme) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Backend Inventory")
                            .font(.title3.weight(.bold))
                            .fontDesign(.rounded)
                        ForEach(overview.backends) { backend in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(backend.kind.rawValue)
                                            .font(.headline)
                                        Text(backend.version ?? "Version unknown")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(backend.status.rawValue.capitalized)
                                        .foregroundStyle(backend.status == .installed ? Color.green : Color.orange)
                                }

                                if let runtimePath = backend.runtimePath {
                                    Text(runtimePath)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .foregroundStyle(.secondary)
                                }

                                Text(backend.capabilities.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if backend.status != .installed {
                                    Button("Install Runtime") {
                                        Task { await model.installBackend(backend) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.loading)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }
}

struct StatCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let detail: String

    var body: some View {
        card(colorScheme: colorScheme) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

func contentBackgroundColors(for colorScheme: ColorScheme) -> [Color] {
    switch colorScheme {
    case .dark:
        return [
            Color(red: 0.15, green: 0.16, blue: 0.12),
            Color(red: 0.07, green: 0.10, blue: 0.11)
        ]
    default:
        return [
            Color(red: 0.95, green: 0.94, blue: 0.88),
            Color(red: 0.80, green: 0.86, blue: 0.78)
        ]
    }
}

func cardFill(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color(red: 0.11, green: 0.13, blue: 0.15).opacity(0.9)
    default:
        return Color.white.opacity(0.74)
    }
}

func cardBorder(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.08)
    default:
        return Color.black.opacity(0.04)
    }
}

func metricPillFill(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.08)
    default:
        return Color.white.opacity(0.62)
    }
}

func groupPanelFill(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.05)
    default:
        return Color.white.opacity(0.44)
    }
}

func assistantBubbleFill(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color(red: 0.15, green: 0.24, blue: 0.20).opacity(0.92)
    default:
        return Color.white.opacity(0.68)
    }
}

func userBubbleFill(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.06)
    default:
        return Color.white.opacity(0.42)
    }
}

func secondaryTextColor(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.72)
    default:
        return Color.secondary
    }
}

struct MetricPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(metricPillFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

func header(_ title: String, subtitle: String, colorScheme: ColorScheme) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 34, weight: .bold, design: .serif))
        Text(subtitle)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(secondaryTextColor(for: colorScheme))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

func card<Content: View>(colorScheme: ColorScheme, @ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder(for: colorScheme), lineWidth: 1)
        )
}

func huggingFaceRepositoryURL(for repoID: String) -> URL? {
    URL(string: "https://huggingface.co/\(repoID)")
}

func displayHubDate(_ value: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let fallbackParser = ISO8601DateFormatter()
    fallbackParser.formatOptions = [.withInternetDateTime]

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none

    if let date = parser.date(from: value) ?? fallbackParser.date(from: value) {
        return formatter.string(from: date)
    }

    return value
}

struct TrayStatusItem: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Image(systemName: model.trayStatusSymbol)
            .symbolRenderingMode(.monochrome)
            .accessibilityLabel("SwiftLM Tray")
    }
}

struct TrayPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let mainWindowID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trayHeader
            Divider()
            traySummary
            Divider()
            trayActions
            Divider()
            trayLoadMenu
            Divider()
            trayLoadedModels
            Divider()
            trayFooter
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var trayHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SwiftLM Tray")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(model.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
    }

    private var traySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            trayMutedText(model.trayServerStatusText)
            trayMutedText(model.trayImportedModelCountText)
            trayMutedText(model.trayLoadedModelCountText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var trayActions: some View {
        VStack(spacing: 0) {
            trayButton("Open SwiftLM") {
                openWindow(id: mainWindowID)
                model.openMainWindow()
            }
            trayButton("Start Selected Model") {
                Task { await model.startPreferredModel() }
            }
            .disabled(model.importedModels.isEmpty || model.loading)
        }
        .padding(.vertical, 6)
    }

    private var trayLoadMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                if model.importedModels.isEmpty {
                    Text("No imported models")
                } else {
                    ForEach(model.importedModels) { record in
                        Button(record.ref.displayName) {
                            Task { await model.loadModelFromTray(record) }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Load Model")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .disabled(model.importedModels.isEmpty || model.loading)
        }
        .padding(18)
    }

    private var trayLoadedModels: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loaded Models:")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            if model.trayLoadedModelNames.isEmpty {
                Text("No models are running.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.trayLoadedModelNames, id: \.self) { name in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.body, design: .rounded))
                }
            }

            trayButton("Unload All Models") {
                Task { await model.unloadAllModels() }
            }
            .disabled(model.trayLoadedModelNames.isEmpty || model.loading)
        }
        .padding(18)
    }

    private var trayFooter: some View {
        VStack(spacing: 0) {
            trayButton("Refresh") {
                Task { try? await model.refresh() }
            }
            trayButton("Quit SwiftLM", shortcut: "q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func trayButton(_ title: String, shortcut: KeyEquivalent? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut.character.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func trayMutedText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

func compactHubMetric(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    switch value {
    case 1_000_000...:
        return "\(formatter.string(from: NSNumber(value: Double(value) / 1_000_000)) ?? "\(value)")M"
    case 1_000...:
        return "\(formatter.string(from: NSNumber(value: Double(value) / 1_000)) ?? "\(value)")K"
    default:
        return "\(value)"
    }
}

func benchmarkScenarioTitle(_ rawValue: String) -> String {
    BenchmarkScenario(rawValue: rawValue)?.title ?? rawValue
}
