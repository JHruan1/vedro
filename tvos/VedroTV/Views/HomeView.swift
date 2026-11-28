import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: VedroTVStore

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 48) {
                if let hero = store.heroItems.first {
                    HeroBannerView(item: hero)
                }

                if !store.resumeItems.isEmpty {
                    PosterShelfView(title: "继续观看", items: store.resumeItems, showProgress: true)
                }

                if !store.nextUpItems.isEmpty {
                    PosterShelfView(title: "接下来播放", items: store.nextUpItems, showProgress: false)
                }

                ForEach(store.shelves) { shelf in
                    PosterShelfView(title: shelf.title, items: shelf.items, showProgress: false)
                }

                if let err = store.errorMessage, !err.isEmpty {
                    Text(err)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 80)
                }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct HeroBannerView: View {
    @EnvironmentObject private var store: VedroTVStore
    let item: VedroMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(
                url: store.core?.imageURL(itemId: item.id, type: "Backdrop", maxWidth: 1920, tag: item.backdropTag)
                    ?? store.core?.imageURL(itemId: item.id, type: "Primary", maxWidth: 1200, tag: item.primaryTag)
            ) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(white: 0.08)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 680)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.45), Color.black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 18) {
                Text(store.activeServerName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                Text(item.name)
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(2)

                if !item.displaySubtitle.isEmpty {
                    Text(item.displaySubtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(3)
                        .frame(maxWidth: 880, alignment: .leading)
                }

                HStack(spacing: 24) {
                    Button {
                        Task { await store.startPlayback(item: item) }
                    } label: {
                        Label("立即播放", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 18)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        DetailView(item: item)
                    } label: {
                        Label("查看详情", systemImage: "info.circle")
                            .font(.headline)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 54)
        }
    }
}

struct PosterShelfView: View {
    let title: String
    let items: [VedroMediaItem]
    let showProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 36) {
                    ForEach(items) { item in
                        NavigationLink {
                            DetailView(item: item)
                        } label: {
                            PosterCardView(item: item, showProgress: showProgress)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
        }
    }
}

struct PosterCardView: View {
    @EnvironmentObject private var store: VedroTVStore
    let item: VedroMediaItem
    let showProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                AsyncImage(
                    url: store.core?.imageURL(itemId: item.id, type: "Primary", maxWidth: 420, tag: item.primaryTag)
                ) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(white: 0.14)
                            Image(systemName: "film")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 240, height: 360)
                .clipped()

                if showProgress && item.resumeProgress > 0.02 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.55))
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * item.resumeProgress)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(item.seriesName ?? item.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)

            if !item.displaySubtitle.isEmpty {
                Text(item.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
