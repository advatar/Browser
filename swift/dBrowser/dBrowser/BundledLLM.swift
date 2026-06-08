import Foundation
import MLXLMCommon
import MLXVLM

enum BundledLLMLoaderSupport: Equatable {
    case supported
    case pendingArchitecture(String)

    var isRunnableWithCurrentSwiftLoader: Bool {
        switch self {
        case .supported:
            return true
        case .pendingArchitecture:
            return false
        }
    }
}

/// Resolves the developer/managed locations where a bundled MLX model may live, without
/// pinning an absolute per-machine path into the source. Candidate roots come from
/// environment overrides first, then the conventional Broom checkout in the user's home
/// directory, then the app's Application Support directory.
enum BundledLLMWorkspace {
    /// Conventional developer checkout root: `~/dev/advatar/Broom`.
    static func defaultDeveloperRoot(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("dev", isDirectory: true)
            .appendingPathComponent("advatar", isDirectory: true)
            .appendingPathComponent("Broom", isDirectory: true)
    }
}

struct BundledLLMProfile: Equatable {
    let displayName: String
    let modelFamily: String
    let size: String
    let quantization: String
    let huggingFaceID: String
    let bundleResourceName: String
    /// Path to the model directory relative to a workspace root, e.g.
    /// `diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx`. Never an absolute machine path.
    let localWorkspaceRelativePath: String
    let localDiskFootprintGB: Double
    let recommendedMinimumMemoryGB: Int
    let swiftPackageURL: String
    let swiftPackageMinimumVersion: String
    let swiftPackageProducts: [String]
    let loaderSupport: BundledLLMLoaderSupport

    var isRecommendedForIPhone: Bool {
        modelFamily == "Gemma 4" && size == "E2B" && quantization == "4-bit MLX"
    }

    var swiftPackageSummary: String {
        "\(swiftPackageURL) @ \(swiftPackageMinimumVersion) (\(swiftPackageProducts.joined(separator: ", ")))"
    }

    /// The model directory's leaf name, e.g. `gemma-4-e2b-it-4bit-mlx`.
    var localWorkspaceModelDirectoryName: String {
        (localWorkspaceRelativePath as NSString).lastPathComponent
    }

    /// Default resolved developer location for the model directory. This is derived from the
    /// current user's home directory at call time rather than stored as an absolute string.
    func localWorkspacePath(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        BundledLLMWorkspace.defaultDeveloperRoot(homeDirectory: homeDirectory)
            .appendingPathComponent(localWorkspaceRelativePath)
            .path
    }

    /// Convenience property using the live home directory.
    var localWorkspacePath: String { localWorkspacePath() }

    var readinessSummary: String {
        switch loaderSupport {
        case .supported:
            return "\(displayName) is ready for local MLX Swift inference through \(swiftPackageProducts.joined(separator: " + "))."
        case .pendingArchitecture(let architecture):
            return "\(displayName) is selected for iPhone, but the current MLX Swift package does not yet register \(architecture)."
        }
    }

    static let gemma4E2B4BitMLX = BundledLLMProfile(
        displayName: "Gemma 4 E2B IT 4-bit MLX",
        modelFamily: "Gemma 4",
        size: "E2B",
        quantization: "4-bit MLX",
        huggingFaceID: "mlx-community/gemma-4-e2b-it-4bit",
        bundleResourceName: "Gemma4E2B4BitMLX",
        localWorkspaceRelativePath: "diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx",
        localDiskFootprintGB: 3.4,
        recommendedMinimumMemoryGB: 8,
        swiftPackageURL: "https://github.com/ml-explore/mlx-swift-lm",
        swiftPackageMinimumVersion: "3.31.3",
        swiftPackageProducts: ["MLXVLM", "MLXLMCommon"],
        loaderSupport: .supported
    )
}

enum BundledLLMModelLocation: Equatable {
    case localDirectory(URL)
    case huggingFace(String)
}

struct BundledLLMSelection: Equatable {
    let profile: BundledLLMProfile

    static let recommended = BundledLLMSelection(profile: .gemma4E2B4BitMLX)

    func bundledModelURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: profile.bundleResourceName, withExtension: nil)
    }

    /// Ordered candidate locations for the local model directory. Environment overrides take
    /// precedence, then the conventional developer checkout, then the app's Application Support
    /// directory. No absolute machine path is hard-coded in source.
    func localWorkspaceCandidateURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var candidates: [URL] = []

        // 1. Explicit full path to the model directory.
        if let explicit = environment["DBROWSER_MLX_MODEL_DIR"], !explicit.isEmpty {
            candidates.append(URL(fileURLWithPath: explicit, isDirectory: true))
        }

        // 2. Workspace roots (env overrides, then the conventional Broom checkout) + relative path.
        var workspaceRoots: [URL] = ["DBROWSER_MLX_WORKSPACE", "BROOM_WORKSPACE"]
            .compactMap { environment[$0] }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        workspaceRoots.append(BundledLLMWorkspace.defaultDeveloperRoot(homeDirectory: homeDirectory))
        for root in workspaceRoots {
            candidates.append(root.appendingPathComponent(profile.localWorkspaceRelativePath, isDirectory: true))
        }

        // 3. App-managed Application Support location.
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            candidates.append(
                appSupport
                    .appendingPathComponent("dBrowser", isDirectory: true)
                    .appendingPathComponent("models", isDirectory: true)
                    .appendingPathComponent(profile.localWorkspaceModelDirectoryName, isDirectory: true)
            )
        }

        return candidates
    }

    func localWorkspaceModelURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "model.safetensors"
        ]

        return localWorkspaceCandidateURLs(
            environment: environment,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).first { url in
            requiredFiles.allSatisfy { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }
        }
    }

    func modelLocation(bundle: Bundle = .main, fileManager: FileManager = .default) -> BundledLLMModelLocation {
        if let bundledURL = bundledModelURL(in: bundle) {
            return .localDirectory(bundledURL)
        }

        if let localURL = localWorkspaceModelURL(fileManager: fileManager) {
            return .localDirectory(localURL)
        }

        return .huggingFace(profile.huggingFaceID)
    }

    func modelConfiguration(bundle: Bundle = .main, fileManager: FileManager = .default) -> ModelConfiguration {
        let registryConfiguration = VLMRegistry.gemma4_E2B_it_4bit

        switch modelLocation(bundle: bundle, fileManager: fileManager) {
        case .localDirectory(let url):
            return ModelConfiguration(
                directory: url,
                defaultPrompt: registryConfiguration.defaultPrompt,
                extraEOSTokens: registryConfiguration.extraEOSTokens,
                toolCallFormat: registryConfiguration.toolCallFormat
            )
        case .huggingFace:
            return registryConfiguration
        }
    }
}
