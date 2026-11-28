import Foundation
import SwiftUI

@MainActor
final class VedroTVStore: ObservableObject {
    @Published var isBootstrapping = true
    @Published var isConnected = false
    @Published var activeServerName = "Vedro"
    @Published var servers: [VedroServerProfile] = []
    @Published var libraries: [VedroMediaItem] = []
    @Published var heroItems: [VedroMediaItem] = []
    @Published var resumeItems: [VedroMediaItem] = []
    @Published var nextUpItems: [VedroMediaItem] = []
    @Published var shelves: [VedroLibraryShelf] = []
    @Published var errorMessage: String?
    @Published var activePlayback: VedroPreparedPlayback?
    @Published var isPreparingPlayback = false

    let core: VedroCoreBridge?

    init() {
        do {
            self.core = try VedroCoreBridge()
        } catch {
            self.core = nil
            self.errorMessage = error.localizedDescription
            self.isBootstrapping = false
        }
    }

    func bootstrap() async {
        guard let core else {
            isBootstrapping = false
            return
        }
        isBootstrapping = true
        errorMessage = nil
        do {
            let raw = try await core.invoke("bootstrap_state") as? [String: Any] ?? [:]
            if let addr = raw["proxy_addr"] as? String {
                core.updateProxyAddr(addr)
            }
            if let rawServers = raw["servers"] as? [[String: Any]] {
                servers = rawServers.compactMap(VedroServerProfile.from)
            }
            if let cachedHome = raw["cached_home"] as? [String: Any] {
                applyHomePayload(cachedHome)
                isConnected = true
            }
            if let activeId = raw["active_server_id"] as? String,
               let active = servers.first(where: { $0.id == activeId }) {
                activeServerName = active.name
                isConnected = true
            } else if let firstAuth = servers.first(where: { $0.hasToken }) {
                activeServerName = firstAuth.name
                isConnected = true
            }
            isBootstrapping = false
            if isConnected {
                await refreshHome()
            }
        } catch {
            errorMessage = error.localizedDescription
            isBootstrapping = false
        }
    }

    func connectAndLogin(url: String, username: String, password: String) async throws {
        guard let core else { throw VedroCoreError.initFailed("核心未就绪") }
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else {
            throw VedroCoreError.rpcFailed("请输入服务器地址（例如 http://192.168.1.10:8096）")
        }
        _ = try await core.invoke("connect_server", params: ["url": trimmedUrl])
        _ = try await core.invoke("login", params: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
        ])
        isConnected = true
        await bootstrap()
    }

    func switchServer(_ server: VedroServerProfile) async {
        guard let core else { return }
        errorMessage = nil
        do {
            _ = try await core.invoke("restore_session", params: ["server_id": server.id])
            activeServerName = server.name
            isConnected = true
            await refreshHome()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHome() async {
        guard let core else { return }
        do {
            let raw = try await core.invoke("get_home", params: [
                "include_suggestions": true,
                "include_favorites": false,
            ]) as? [String: Any] ?? [:]
            applyHomePayload(raw)
            isConnected = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyHomePayload(_ raw: [String: Any]) {
        if let caps = raw["capabilities"] as? [String: Any],
           let name = caps["server_name"] as? String, !name.isEmpty {
            activeServerName = name
        }
        let views = ((raw["views"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        let popular = ((raw["popular"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        let resume = ((raw["resume"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        let nextUp = ((raw["next_up"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        let latestRaw = (raw["latest_by_library"] as? [[String: Any]]) ?? []

        libraries = views
        resumeItems = resume
        nextUpItems = nextUp

        var newShelves: [VedroLibraryShelf] = []
        for entry in latestRaw {
            guard let libDict = entry["library"] as? [String: Any],
                  let lib = VedroMediaItem.from(libDict) else { continue }
            let items = ((entry["items"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
            if !items.isEmpty {
                newShelves.append(VedroLibraryShelf(id: lib.id, title: "最新 · \(lib.name)", items: items))
            }
        }
        shelves = newShelves

        if !popular.isEmpty {
            heroItems = Array(popular.prefix(6))
        } else if let firstShelf = newShelves.first {
            heroItems = Array(firstShelf.items.prefix(6))
        } else {
            heroItems = Array(resume.prefix(4))
        }
    }

    func fetchLibraryItems(parentId: String, limit: Int = 60) async -> [VedroMediaItem] {
        guard let core else { return [] }
        do {
            let raw = try await core.invoke("get_items", params: [
                "parent_id": parentId,
                "recursive": true,
                "include_item_types": "Movie,Series",
                "sort_by": "DateCreated",
                "sort_order": "Descending",
                "limit": limit,
            ]) as? [String: Any] ?? [:]
            return ((raw["items"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        } catch {
            return []
        }
    }

    func search(query: String) async -> [VedroMediaItem] {
        guard let core else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        do {
            let raw = try await core.invoke("get_items", params: [
                "search_term": q,
                "recursive": true,
                "include_item_types": "Movie,Series",
                "limit": 40,
            ]) as? [String: Any] ?? [:]
            return ((raw["items"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        } catch {
            return []
        }
    }

    func fetchItemDetail(itemId: String) async -> VedroMediaItem? {
        guard let core else { return nil }
        do {
            let raw = try await core.invoke("get_item", params: ["item_id": itemId]) as? [String: Any] ?? [:]
            if let itemDict = raw["item"] as? [String: Any] {
                return VedroMediaItem.from(itemDict)
            }
        } catch {}
        return nil
    }

    func fetchSeasons(seriesId: String) async -> [VedroMediaItem] {
        guard let core else { return [] }
        do {
            let raw = try await core.invoke("get_seasons", params: ["series_id": seriesId]) as? [String: Any] ?? [:]
            return ((raw["items"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        } catch {
            return []
        }
    }

    func fetchEpisodes(seriesId: String, seasonId: String) async -> [VedroMediaItem] {
        guard let core else { return [] }
        do {
            let raw = try await core.invoke("get_episodes", params: [
                "series_id": seriesId,
                "season_id": seasonId,
                "limit": 200,
            ]) as? [String: Any] ?? [:]
            return ((raw["items"] as? [[String: Any]]) ?? []).compactMap(VedroMediaItem.from)
        } catch {
            return []
        }
    }

    func startPlayback(item: VedroMediaItem, mediaSourceId: String? = nil) async {
        guard let core else { return }
        isPreparingPlayback = true
        errorMessage = nil
        defer { isPreparingPlayback = false }
        do {
            var params: [String: Any] = [
                "item_id": item.id,
                "inspect_header": false,
            ]
            if let mediaSourceId, !mediaSourceId.isEmpty {
                params["media_source_id"] = mediaSourceId
            }
            let raw = try await core.invoke("prepare_playback", params: params) as? [String: Any] ?? [:]
            guard let proxyStr = raw["proxy_url"] as? String,
                  let proxyUrl = URL(string: proxyStr) else {
                errorMessage = "无法获取流媒体地址"
                return
            }
            let upstreamUrl = (raw["upstream_url"] as? String).flatMap(URL.init(string:))
            let sourceId = (raw["media_source_id"] as? String) ?? mediaSourceId ?? ""
            let sessionId = (raw["play_session_id"] as? String) ?? ""
            let streamId = (raw["stream_id"] as? String) ?? ""
            let sourceDict = raw["media_source"] as? [String: Any]
            let container = ((sourceDict?["Container"] as? String) ?? "").lowercased()
            let badges = raw["badges"] as? [String: Any]
            let hdrBadge = badges?["hdr_format"] as? String
            let isAtmos = (badges?["is_dolby_atmos"] as? Bool) == true
            let audioBadge = isAtmos ? "Dolby Atmos" : (badges?["audio_codec"] as? String)

            activePlayback = VedroPreparedPlayback(
                item: item,
                mediaSourceId: sourceId,
                playSessionId: sessionId,
                streamId: streamId,
                proxyUrl: proxyUrl,
                upstreamUrl: upstreamUrl,
                container: container,
                hdrBadge: hdrBadge,
                audioBadge: audioBadge,
                startSeconds: item.resumeSeconds > 5 ? item.resumeSeconds : 0
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reportPlaybackStart(_ pb: VedroPreparedPlayback, positionSecs: Double) {
        guard let core else { return }
        Task {
            _ = try? await core.invoke("report_playback_start", params: [
                "item_id": pb.item.id,
                "media_source_id": pb.mediaSourceId,
                "play_session_id": pb.playSessionId,
                "position_ticks": Int64(positionSecs * 10_000_000.0),
                "run_time_ticks": pb.item.runTimeTicks,
                "is_paused": false,
            ])
        }
    }

    func reportPlaybackProgress(_ pb: VedroPreparedPlayback, positionSecs: Double, isPaused: Bool) {
        guard let core else { return }
        Task {
            _ = try? await core.invoke("report_playback_progress", params: [
                "item_id": pb.item.id,
                "media_source_id": pb.mediaSourceId,
                "play_session_id": pb.playSessionId,
                "position_ticks": Int64(positionSecs * 10_000_000.0),
                "run_time_ticks": pb.item.runTimeTicks,
                "is_paused": isPaused,
            ])
        }
    }

    func reportPlaybackStopped(_ pb: VedroPreparedPlayback, positionSecs: Double) {
        guard let core else { return }
        Task {
            _ = try? await core.invoke("report_playback_stopped", params: [
                "item_id": pb.item.id,
                "media_source_id": pb.mediaSourceId,
                "play_session_id": pb.playSessionId,
                "stream_id": pb.streamId,
                "position_ticks": Int64(positionSecs * 10_000_000.0),
                "run_time_ticks": pb.item.runTimeTicks,
                "is_paused": true,
            ])
            _ = try? await core.invoke("player_stop", params: [
                "stream_id": pb.streamId,
            ])
        }
    }
}
