import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: VedroTVStore
    @State private var selectedLibraryId: String = ""
    @State private var items: [VedroMediaItem] = []
    @State private var isLoading = false

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 40)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(store.libraries) { lib in
                            if selectedLibraryId == lib.id {
                                Button(lib.name) {
                                    selectedLibraryId = lib.id
                                    Task { await loadLibrary(lib.id) }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button(lib.name) {
                                    selectedLibraryId = lib.id
                                    Task { await loadLibrary(lib.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 12)
                }

                if isLoading {
                    ProgressView("正在加载媒体库…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 44) {
                        ForEach(items) { item in
                            NavigationLink {
                                DetailView(item: item)
                            } label: {
                                PosterCardView(item: item, showProgress: false)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
            .padding(.top, 24)
        }
        .task {
            if selectedLibraryId.isEmpty, let first = store.libraries.first {
                selectedLibraryId = first.id
                await loadLibrary(first.id)
            }
        }
    }

    private func loadLibrary(_ id: String) async {
        isLoading = true
        items = await store.fetchLibraryItems(parentId: id)
        isLoading = false
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: VedroTVStore
    @State private var query = ""
    @State private var results: [VedroMediaItem] = []
    @State private var searching = false

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 40)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(spacing: 24) {
                    TextField("搜索电影、剧集或演员…", text: $query)
                        .onSubmit {
                            Task { await performSearch() }
                        }
                    Button("搜索") {
                        Task { await performSearch() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 80)
                .padding(.top, 30)

                if searching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if results.isEmpty && !query.isEmpty {
                    Text("未找到与「\(query)」相关的影视内容")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 44) {
                        ForEach(results) { item in
                            NavigationLink {
                                DetailView(item: item)
                            } label: {
                                PosterCardView(item: item, showProgress: false)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
    }

    private func performSearch() async {
        searching = true
        results = await store.search(query: query)
        searching = false
    }
}

struct ServerSetupView: View {
    @EnvironmentObject private var store: VedroTVStore
    @State private var serverUrl = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var localError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vedro for Apple TV")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Rust 核心流媒体代理 + Apple TV 原生硬件杜比视界 & 空间音频引擎")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !store.servers.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("已保存服务器")
                            .font(.headline)
                        ForEach(store.servers) { srv in
                            Button {
                                Task { await store.switchServer(srv) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(srv.name).font(.headline)
                                        Text("\(srv.url) · \(srv.username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if srv.name == store.activeServerName && store.isConnected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("连接新 Emby / Jellyfin / EmbyGo 服务器")
                        .font(.headline)

                    TextField("服务器地址（如 http://192.168.1.10:8096）", text: $serverUrl)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    TextField("用户名", text: $username)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)

                    if let err = localError ?? store.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    Button {
                        Task { await submitLogin() }
                    } label: {
                        if connecting {
                            ProgressView()
                        } else {
                            Text("连接并登录")
                                .font(.headline)
                                .padding(.horizontal, 24)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connecting || serverUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("画质与音频说明")
                        .font(.headline)
                    Text("请在 Apple TV「设置 → 视频和音频 → 匹配内容」中同时开启「匹配动态范围」与「匹配帧速率」，播放杜比视界 / HDR10 与杜比全景声片源时将自动触发系统原生硬件管线。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(80)
        }
    }

    private func submitLogin() async {
        connecting = true
        localError = nil
        defer { connecting = false }
        do {
            try await store.connectAndLogin(url: serverUrl, username: username, password: password)
            password = ""
        } catch {
            localError = error.localizedDescription
        }
    }
}
