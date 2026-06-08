//
//  LocalLLMPanelViews.swift
//  dBrowser
//
//  Extracted from ContentView.swift to reduce the ContentView god file.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LocalLLMPanelView: View {
    @ObservedObject var browser: BrowserViewModel

    private var state: LocalLLMManagementState {
        browser.localLLMState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "Local LLMs",
                    systemImage: BrowserPanel.localLLM.systemImage,
                    subtitle: "Manage local models, runtimes, and the SwiftLM control plane used by Copilot."
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        LocalLLMStatusBadge(mode: state.mode, health: state.health)
                        Text(state.statusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        LocalLLMMetricTile(title: "Endpoint", value: state.baseURL, systemImage: "point.3.connected.trianglepath.dotted")
                        LocalLLMMetricTile(title: "Models", value: state.importedModelCountText, systemImage: "shippingbox")
                        LocalLLMMetricTile(title: "Engines", value: state.activeEngineCountText, systemImage: "bolt.horizontal")
                        LocalLLMMetricTile(title: "Memory", value: state.hardware.unifiedMemory, systemImage: "memorychip")
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await browser.connectLocalLLMControlPlane() }
                        } label: {
                            Label("Connect", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isWorking)
                        .accessibilityIdentifier("local-llm-connect")

                        Button {
                            Task { await browser.bootstrapLocalLLMControlPlane() }
                        } label: {
                            Label("Start Embedded", systemImage: "play.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isWorking)
                        .accessibilityIdentifier("local-llm-bootstrap")

                        Button {
                            Task { await browser.refreshLocalLLMManagement() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isWorking)
                        .accessibilityIdentifier("local-llm-refresh")
                    }

                    if state.isWorking {
                        ProgressView("Updating SwiftLM state...")
                            .font(.caption)
                    }

                    if let error = state.lastError {
                        Text(error)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                LocalLLMRecommendedModelView(browser: browser, recommended: state.recommendedImport, isWorking: state.isWorking)
                LocalLLMHardwareView(hardware: state.hardware, developerKeyPreview: state.developerKeyPreview)
                LocalLLMBackendsView(browser: browser, backends: state.backends, isWorking: state.isWorking)
                LocalLLMModelsView(browser: browser, models: state.models, isWorking: state.isWorking)
                LocalLLMEnginesView(browser: browser, engines: state.activeEngines, isWorking: state.isWorking)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-local-llms")
        .task {
            guard browser.localLLMState.mode == .disconnected else { return }
            await browser.refreshLocalLLMManagement()
        }
    }
}

struct LocalLLMStatusBadge: View {
    let mode: LocalLLMControlPlaneMode
    let health: String

    private var color: Color {
        switch mode {
        case .embedded, .connected:
            return health == "ok" ? .green : .orange
        case .disconnected:
            return .orange
        case .unavailable:
            return .secondary
        }
    }

    var body: some View {
        Label(mode.title, systemImage: mode == .embedded ? "server.rack" : "cpu")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LocalLLMMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LocalLLMRecommendedModelView: View {
    @ObservedObject var browser: BrowserViewModel
    let recommended: LocalLLMRecommendedImport
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Recommended iPhone Model", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(recommended.sourceKind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(recommended.displayName)
                .font(.title3.weight(.semibold))
            Text(recommended.readinessSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(recommended.sourceRef)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(recommended.packageSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    Task { await browser.importRecommendedLocalLLM() }
                } label: {
                    Label("Import to SwiftLM", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
                .accessibilityIdentifier("local-llm-import-recommended")

                Button {
                    browser.selectLLMModel(LLMModelRegistry.localGemmaID)
                } label: {
                    Label("Use for Copilot", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(browser.selectedLLMModelID == LLMModelRegistry.localGemmaID)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LocalLLMHardwareView: View {
    let hardware: LocalLLMHardwareSummary
    let developerKeyPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hardware", systemImage: "desktopcomputer")
                .font(.headline)
            Text(hardware.chipFamily)
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                LocalLLMMetricTile(title: "Unified Memory", value: hardware.unifiedMemory, systemImage: "memorychip")
                LocalLLMMetricTile(title: "Free Disk", value: hardware.freeDisk, systemImage: "internaldrive")
                LocalLLMMetricTile(title: "GPU Cores", value: hardware.gpuCores, systemImage: "cpu")
                LocalLLMMetricTile(title: "API Key", value: developerKeyPreview ?? "none", systemImage: "key")
            }
            Text(hardware.osVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LocalLLMBackendsView: View {
    @ObservedObject var browser: BrowserViewModel
    let backends: [LocalLLMBackendSummary]
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Runtimes", systemImage: "gearshape.2")
                .font(.headline)

            if backends.isEmpty {
                EmptyPanelView(title: "No runtime data", message: "Connect or start the SwiftLM control plane to inspect MLX and vLLM runtime availability.")
            } else {
                ForEach(backends) { backend in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: backend.status == "installed" ? "checkmark.circle" : "wrench.and.screwdriver")
                            .frame(width: 22)
                            .foregroundStyle(backend.status == "installed" ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backend.kind)
                                .font(.subheadline.weight(.semibold))
                            Text("\(backend.status) / \(backend.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(backend.runtimePath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !backend.capabilities.isEmpty {
                                Text(backend.capabilities.prefix(5).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await browser.installLocalLLMBackend(backend.id) }
                        } label: {
                            Label("Install", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking || !backend.canInstall)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

struct LocalLLMModelsView: View {
    @ObservedObject var browser: BrowserViewModel
    let models: [LocalLLMModelSummary]
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Imported Models", systemImage: "shippingbox")
                .font(.headline)

            if models.isEmpty {
                EmptyPanelView(title: "No imported models", message: "Import the recommended Gemma model or connect to an existing SwiftLM library.")
            } else {
                ForEach(models) { model in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .frame(width: 22)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(model.id)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(model.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(model.status)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.status == "ready" ? Color.green : Color.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                            LocalLLMMetricTile(title: "Family", value: model.family, systemImage: "folder")
                            LocalLLMMetricTile(title: "Architecture", value: model.architecture, systemImage: "cpu")
                            LocalLLMMetricTile(title: "Quant", value: model.quantization, systemImage: "slider.horizontal.3")
                            LocalLLMMetricTile(title: "Context", value: model.contextWindow, systemImage: "text.alignleft")
                            LocalLLMMetricTile(title: "Disk", value: model.sizeOnDisk, systemImage: "internaldrive")
                        }

                        Text(model.capabilities.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if !model.warnings.isEmpty {
                            Text(model.warnings.prefix(3).joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(3)
                        }

                        HStack(spacing: 8) {
                            Button {
                                Task { await browser.inspectLocalLLMModel(model.id) }
                            } label: {
                                Label("Inspect", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isWorking || !model.canInspect)

                            Button {
                                Task { await browser.validateLocalLLMModel(model.id) }
                            } label: {
                                Label("Validate", systemImage: "checkmark.shield")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isWorking || !model.canValidate)

                            Button {
                                Task { await browser.warmLocalLLMModel(model.id) }
                            } label: {
                                Label("Warm", systemImage: "flame")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking || !model.canWarm)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

struct LocalLLMEnginesView: View {
    @ObservedObject var browser: BrowserViewModel
    let engines: [LocalLLMEngineSummary]
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Running Engines", systemImage: "bolt.horizontal")
                .font(.headline)

            if engines.isEmpty {
                EmptyPanelView(title: "No running engines", message: "Warm an imported model to start a local SwiftLM runtime.")
            } else {
                ForEach(engines) { engine in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: engine.isWarm ? "bolt.circle.fill" : "bolt.circle")
                            .frame(width: 22)
                            .foregroundStyle(engine.isWarm ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(engine.modelID)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Backend \(engine.backendID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Queue \(engine.queueDepth) / \(engine.outputTokensPerSecond) / \(engine.peakMemory)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await browser.stopLocalLLMEngine(engine.id) }
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

