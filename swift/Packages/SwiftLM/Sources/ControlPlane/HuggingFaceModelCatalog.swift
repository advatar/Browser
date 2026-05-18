import Contracts
import Foundation

public protocol ModelCatalogSearching: Sendable {
    func searchModels(query: String, limit: Int) async throws -> [ModelSearchResult]
    func fetchModelCard(id: String) async throws -> ModelCatalogCard
}

public struct HuggingFaceModelCatalog: ModelCatalogSearching {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "https://huggingface.co")!) {
        self.baseURL = baseURL
    }

    public func searchModels(query: String, limit: Int) async throws -> [ModelSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        var components = URLComponents(url: apiModelsBaseURL(), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search", value: trimmedQuery),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 40))")
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let payload: [HuggingFaceModelPayload] = try await fetchJSON(url: url)
        return payload.compactMap(\.searchResult)
    }

    public func fetchModelCard(id: String) async throws -> ModelCatalogCard {
        let detailsURL = modelDetailsURL(repoID: id)
        let payload: HuggingFaceModelDetailsPayload = try await fetchJSON(url: detailsURL)
        guard let card = payload.modelCard(
            readme: try await fetchReadme(repoID: id),
            repositoryURL: repositoryURL(repoID: id)
        ) else {
            throw URLError(.cannotParseResponse)
        }
        return card
    }

    private func fetchJSON<Response: Decodable>(url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLM", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func fetchReadme(repoID: String) async throws -> String? {
        let url = rawReadmeURL(repoID: repoID)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/markdown, text/plain;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLM", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 {
            return nil
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func apiModelsBaseURL() -> URL {
        var url = baseURL
        url.append(path: "api")
        url.append(path: "models")
        return url
    }

    private func modelDetailsURL(repoID: String) -> URL {
        urlForRepositoryPath(prefix: ["api", "models"], repoID: repoID)
    }

    private func repositoryURL(repoID: String) -> URL {
        urlForRepositoryPath(prefix: [], repoID: repoID)
    }

    private func rawReadmeURL(repoID: String) -> URL {
        urlForRepositoryPath(prefix: [], repoID: repoID, suffix: ["raw", "main", "README.md"])
    }

    private func urlForRepositoryPath(prefix: [String], repoID: String, suffix: [String] = []) -> URL {
        let repoComponents = repoID.split(separator: "/").map(String.init)
        return (prefix + repoComponents + suffix).reduce(baseURL) { partialURL, component in
            partialURL.appending(path: component)
        }
    }
}

private struct HuggingFaceModelPayload: Decodable {
    let id: String?
    let modelId: String?
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?
    let libraryName: String?
    let createdAt: String?
    let tags: [String]?

    var searchResult: ModelSearchResult? {
        guard let repoID = id ?? modelId else {
            return nil
        }
        let displayName = repoID.split(separator: "/").last.map(String.init) ?? repoID
        return ModelSearchResult(
            id: repoID,
            displayName: displayName,
            downloads: downloads,
            likes: likes,
            pipelineTag: pipelineTag,
            libraryName: libraryName,
            createdAt: createdAt,
            artifactFormats: HubModelFormat.infer(
                repoID: repoID,
                libraryName: libraryName,
                tags: tags ?? []
            ),
            tags: tags ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case downloads
        case likes
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case createdAt
        case tags
    }
}

private struct HuggingFaceModelDetailsPayload: Decodable {
    let id: String?
    let modelId: String?
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?
    let libraryName: String?
    let createdAt: String?
    let lastModified: String?
    let tags: [String]?
    let cardData: HuggingFaceCardData?
    let siblings: [HuggingFaceSibling]?

    func modelCard(readme: String?, repositoryURL: URL) -> ModelCatalogCard? {
        guard let repoID = id ?? modelId else {
            return nil
        }

        let siblingFiles = siblings?.map(\.rfilename) ?? []
        let mergedTags = Array(Set((tags ?? []) + (cardData?.tags ?? []))).sorted()
        let resolvedLibrary = libraryName ?? cardData?.libraryName
        let resolvedPipeline = pipelineTag ?? cardData?.pipelineTag
        let displayName = repoID.split(separator: "/").last.map(String.init) ?? repoID

        return ModelCatalogCard(
            id: repoID,
            displayName: displayName,
            downloads: downloads,
            likes: likes,
            pipelineTag: resolvedPipeline,
            libraryName: resolvedLibrary,
            license: cardData?.license,
            baseModel: cardData?.baseModel.first,
            languages: cardData?.language ?? [],
            createdAt: createdAt,
            lastModified: lastModified,
            artifactFormats: HubModelFormat.infer(
                repoID: repoID,
                libraryName: resolvedLibrary,
                tags: mergedTags,
                siblingFiles: siblingFiles
            ),
            tags: mergedTags,
            siblingFiles: siblingFiles,
            readme: readme,
            repositoryURL: repositoryURL.absoluteString
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case downloads
        case likes
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case createdAt
        case lastModified
        case tags
        case cardData
        case siblings
    }
}

private struct HuggingFaceCardData: Decodable {
    let license: String?
    let language: [String]?
    let pipelineTag: String?
    let baseModel: [String]
    let tags: [String]?
    let libraryName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        language = try container.decodeIfPresent(StringListValue.self, forKey: .language)?.values
        pipelineTag = try container.decodeIfPresent(String.self, forKey: .pipelineTag)
        baseModel = try container.decodeIfPresent(StringListValue.self, forKey: .baseModel)?.values ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        libraryName = try container.decodeIfPresent(String.self, forKey: .libraryName)
    }

    enum CodingKeys: String, CodingKey {
        case license
        case language
        case pipelineTag = "pipeline_tag"
        case baseModel = "base_model"
        case tags
        case libraryName = "library_name"
    }
}

private struct StringListValue: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
            return
        }
        values = try container.decode([String].self)
    }
}

private struct HuggingFaceSibling: Decodable {
    let rfilename: String
}
