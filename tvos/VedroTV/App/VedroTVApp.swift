import SwiftUI

@main
struct VedroTVApp: App {
    @StateObject private var store = VedroTVStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                }
                .fullScreenCover(item: $store.activePlayback) { playback in
                    CinemaPlayerView(playback: playback)
                        .environmentObject(store)
                        .ignoresSafeArea()
                }
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var store: VedroTVStore

    var body: some View {
        Group {
            if store.isBootstrapping {
                VStack(spacing: 24) {
                    ProgressView()
                    Text("Vedro 正在连接媒体库…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else if !store.isConnected {
                ServerSetupView()
            } else {
                TabView {
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label("首页", systemImage: "house.fill")
                    }

                    NavigationStack {
                        LibraryView()
                    }
                    .tabItem {
                        Label("媒体库", systemImage: "square.grid.2x2.fill")
                    }

                    NavigationStack {
                        SearchView()
                    }
                    .tabItem {
                        Label("搜索", systemImage: "magnifyingglass")
                    }

                    NavigationStack {
                        ServerSetupView()
                    }
                    .tabItem {
                        Label("服务器", systemImage: "server.rack")
                    }
                }
            }
        }
    }
}
