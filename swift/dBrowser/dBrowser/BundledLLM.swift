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

struct BundledLLMProfile: Equatable {
    let displayName: String
    let modelFamily: String
    let size: String
    let quantization: String
    let huggingFaceID: String
    let bundleResourceName: String
    let localWorkspacePath: String
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
        localWorkspacePath: "/Users/johansellstrom/dev/advatar/Broom/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx",
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

    func localWorkspaceModelURL(fileManager: FileManager = .default) -> URL? {
        let url = URL(fileURLWithPath: profile.localWorkspacePath, isDirectory: true)
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "model.safetensors"
        ]

        guard requiredFiles.allSatisfy({ fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }) else {
            return nil
        }
        return url
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
