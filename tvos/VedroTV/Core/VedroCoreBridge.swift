import Foundation

// MARK: - Rust Core FFI Bridge

enum VedroCoreError: LocalizedError {
    case initFailed(String)
    case invalidResponse
    case rpcFailed(String)

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "核心初始化失败：\(msg)"
        case .invalidResponse: return "核心返回了无法解析的响应"
        case .rpcFailed(let msg): return msg
        }
    }
}

final class VedroCoreBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vedro.tv.ffi", qos: .userInitiated)
    private var handle: OpaquePointer?
    private(set) var proxyAddr: String = ""

    init() throws {
        let supportDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = supportDir.appendingPathComponent("VedroTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("vedro_tv.db").path

        let ptr: OpaquePointer? = dbPath.withCString { cPath in
            vedro_init(cPath)
        }
        guard let validPtr = ptr else {
            let errStr: String
            if let rawErr = vedro_last_init_error() {
                errStr = String(cString: rawErr)
                vedro_free_string(rawErr)
            } else {
                errStr = "unknown error"
            }
            throw VedroCoreError.initFailed(errStr)
        }
        self.handle = validPtr
    }

    deinit {
        if let h = handle {
            vedro_destroy(h)
            handle = nil
        }
    }

    var coreVersion: String {
        guard let cStr = vedro_version() else { return "1.0" }
        return String(cString: cStr)
    }

    func updateProxyAddr(_ addr: String) {
        if !addr.isEmpty {
            proxyAddr = addr
        }
    }

    func proxySpeedBps() -> UInt64 {
        guard let h = handle else { return 0 }
        return vedro_proxy_speed_bps(h)
    }

    func invoke(_ method: String, params: [String: Any] = [:]) async throws -> Any {
        guard let h = handle else {
            throw VedroCoreError.initFailed("runtime destroyed")
        }
        let paramsData = try JSONSerialization.data(withJSONObject: params, options: [])
        let paramsJson = String(data: paramsData, encoding: .utf8) ?? "{}"

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let rawPtr: UnsafeMutablePointer<CChar>? = method.withCString { cMethod in
                    paramsJson.withCString { cParams in
                        vedro_invoke(h, cMethod, cParams)
                    }
                }
                guard let ptr = rawPtr else {
                    continuation.resume(throwing: VedroCoreError.invalidResponse)
                    return
                }
                let rawJson = String(cString: ptr)
                vedro_free_string(ptr)

                guard let data = rawJson.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(throwing: VedroCoreError.invalidResponse)
                    return
                }
                if (obj["ok"] as? Bool) == true {
                    continuation.resume(returning: obj["data"] ?? [String: Any]())
                } else {
                    let msg = (obj["error"] as? String) ?? "未知错误"
                    continuation.resume(throwing: VedroCoreError.rpcFailed(msg))
                }
            }
        }
    }

    func imageURL(itemId: String, type: String = "Primary", maxWidth: Int = 500, tag: String? = nil) -> URL? {
        guard !proxyAddr.isEmpty, !itemId.isEmpty else { return nil }
        var comps = URLComponents(string: "http://\(proxyAddr)/img/Items/\(itemId)/Images/\(type)")
        var queryItems = [URLQueryItem(name: "maxWidth", value: "\(maxWidth)")]
        if let tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        comps?.queryItems = queryItems
        return comps?.url
    }
}

// MARK: - Domain Models

struct VedroServerProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let username: String
    let dialect: String
    let hasToken: Bool

    static func from(_ dict: [String: Any]) -> VedroServerProfile? {
        guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = (dict["url"] as? String) ?? ""
        let username = (dict["username"] as? String) ?? ""
        let dialect = (dict["dialect"] as? String) ?? "emby"
        let token = (dict["access_token"] as? String) ?? ""
        return VedroServerProfile(
            id: id,
            name: name.isEmpty ? url : name,
            url: url,
            username: username,
            dialect: dialect,
            hasToken: !token.isEmpty
        )
    }
}

struct VedroMediaSource: Identifiable, Hashable {
    let id: String
    let name: String
    let container: String
    let sizeBytes: Int64
    let bitrate: Int64
    let summary: String

    static func from(_ dict: [String: Any]) -> VedroMediaSource? {
        guard let id = dict["Id"] as? String ?? (dict["id"] as? String), !id.isEmpty else { return nil }
        let name = (dict["Name"] as? String) ?? (dict["name"] as? String) ?? "默认版本"
        let container = ((dict["Container"] as? String) ?? (dict["container"] as? String) ?? "").uppercased()
        let size = (dict["Size"] as? NSNumber)?.int64Value ?? (dict["size"] as? NSNumber)?.int64Value ?? 0
        let bitrate = (dict["Bitrate"] as? NSNumber)?.int64Value ?? 0
        var parts: [String] = []
        if !container.isEmpty { parts.append(container) }
        if size > 0 {
            let gb = Double(size) / 1_073_741_824.0
            parts.append(gb >= 1.0 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(size) / 1_048_576.0))
        }
        if bitrate > 0 {
            parts.append(String(format: "%.1f Mbps", Double(bitrate) / 1_000_000.0))
        }
        return VedroMediaSource(
            id: id,
            name: name,
            container: container,
            sizeBytes: size,
            bitrate: bitrate,
            summary: parts.joined(separator: " · ")
        )
    }
}

struct VedroMediaItem: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let overview: String
    let year: Int?
    let rating: Double?
    let seriesId: String?
    let seriesName: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let runTimeTicks: Int64
    let playbackPositionTicks: Int64
    let primaryTag: String?
    let backdropTag: String?
    let mediaSources: [VedroMediaSource]

    var displaySubtitle: String {
        if let s = seasonNumber, let e = episodeNumber {
            return "S\(s) · E\(e)"
        }
        var parts: [String] = []
        if let y = year { parts.append("\(y)") }
        if let r = rating, r > 0 { parts.append(String(format: "★ %.1f", r)) }
        return parts.joined(separator: "  ")
    }

    var resumeProgress: Double {
        guard runTimeTicks > 0, playbackPositionTicks > 0 else { return 0 }
        return min(1.0, max(0.0, Double(playbackPositionTicks) / Double(runTimeTicks)))
    }

    var resumeSeconds: Double {
        Double(playbackPositionTicks) / 10_000_000.0
    }

    static func from(_ dict: [String: Any]) -> VedroMediaItem? {
        guard let id = dict["Id"] as? String ?? (dict["id"] as? String), !id.isEmpty else { return nil }
        let name = (dict["Name"] as? String) ?? (dict["name"] as? String) ?? "未命名"
        let type = (dict["Type"] as? String) ?? (dict["type"] as? String) ?? "Movie"
        let overview = (dict["Overview"] as? String) ?? ""
        let year = (dict["ProductionYear"] as? NSNumber)?.intValue
        let rating = (dict["CommunityRating"] as? NSNumber)?.doubleValue
        let seriesId = dict["SeriesId"] as? String
        let seriesName = dict["SeriesName"] as? String
        let seasonNum = (dict["ParentIndexNumber"] as? NSNumber)?.intValue
        let epNum = (dict["IndexNumber"] as? NSNumber)?.intValue
        let runTimeTicks = (dict["RunTimeTicks"] as? NSNumber)?.int64Value ?? 0
        let userData = dict["UserData"] as? [String: Any]
        let posTicks = (userData?["PlaybackPositionTicks"] as? NSNumber)?.int64Value ?? 0
        let imageTags = dict["ImageTags"] as? [String: Any]
        let primaryTag = imageTags?["Primary"] as? String
        let backdropTags = dict["BackdropImageTags"] as? [String]
        let backdropTag = backdropTags?.first
        let rawSources = (dict["MediaSources"] as? [[String: Any]]) ?? []
        let sources = rawSources.compactMap(VedroMediaSource.from)

        return VedroMediaItem(
            id: id,
            name: name,
            type: type,
            overview: overview,
            year: year,
            rating: rating,
            seriesId: seriesId,
            seriesName: seriesName,
            seasonNumber: seasonNum,
            episodeNumber: epNum,
            runTimeTicks: runTimeTicks,
            playbackPositionTicks: posTicks,
            primaryTag: primaryTag,
            backdropTag: backdropTag,
            mediaSources: sources
        )
    }
}

struct VedroLibraryShelf: Identifiable {
    let id: String
    let title: String
    let items: [VedroMediaItem]
}

struct VedroPreparedPlayback: Identifiable {
    let id = UUID()
    let item: VedroMediaItem
    let mediaSourceId: String
    let playSessionId: String
    let streamId: String
    let proxyUrl: URL
    let upstreamUrl: URL?
    let container: String
    let hdrBadge: String?
    let audioBadge: String?
    let startSeconds: Double
}
