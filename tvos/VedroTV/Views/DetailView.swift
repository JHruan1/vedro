import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: VedroTVStore
    let item: VedroMediaItem

    @State private var fullItem: VedroMediaItem?
    @State private var seasons: [VedroMediaItem] = []
    @State private var selectedSeasonId: String = ""
    @State private var episodes: [VedroMediaItem] = []
    @State private var selectedSourceId: String?

    private var active: VedroMediaItem { fullItem ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                heroSection
                if active.mediaSources.count > 1 {
                    sourcesSection
                }
                if !seasons.isEmpty {
                    seasonsSection
                }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
        .task {
            if let detailed = await store.fetchItemDetail(itemId: item.id) {
                fullItem = detailed
                selectedSourceId = detailed.mediaSources.first?.id
            }
            if active.type == "Series" {
                let s = await store.fetchSeasons(seriesId: active.id)
                seasons = s
                if let first = s.first {
                    selectedSeasonId = first.id
                    episodes = await store.fetchEpisodes(seriesId: active.id, seasonId: first.id)
                }
            }
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(
                url: store.core?.imageURL(itemId: active.id, type: "Backdrop", maxWidth: 1920, tag: active.backdropTag)
                    ?? store.core?.imageURL(itemId: active.id, type: "Primary", maxWidth: 1200, tag: active.primaryTag)
            ) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(white: 0.08)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 620)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.5), Color.black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            HStack(alignment: .bottom, spacing: 42) {
                AsyncImage(
                    url: store.core?.imageURL(itemId: active.id, type: "Primary", maxWidth: 480, tag: active.primaryTag)
                ) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(white: 0.16)
                    }
                }
                .frame(width: 240, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 16) {
                    Text(active.name)
                        .font(.system(size: 50, weight: .bold))
                        .lineLimit(2)

                    if !active.displaySubtitle.isEmpty {
                        Text(active.displaySubtitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if !active.overview.isEmpty {
                        Text(active.overview)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(4)
                            .frame(maxWidth: 960, alignment: .leading)
                    }

                    HStack(spacing: 22) {
                        Button {
                            Task {
                                if active.type == "Series", let firstEp = episodes.first {
                                    await store.startPlayback(item: firstEp)
                                } else {
                                    await store.startPlayback(item: active, mediaSourceId: selectedSourceId)
                                }
                            }
                        } label: {
                            if store.isPreparingPlayback {
                                ProgressView()
                            } else {
                                Label(
                                    active.resumeSeconds > 10 ? "继续播放" : "立即播放",
                                    systemImage: "play.fill"
                                )
                                .font(.headline)
                                .padding(.horizontal, 18)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isPreparingPlayback)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 44)
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("片源版本")
                .font(.headline)
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(active.mediaSources) { src in
                        sourceChip(src)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func sourceChip(_ src: VedroMediaSource) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            Text(src.name).font(.callout).lineLimit(1)
            if !src.summary.isEmpty {
                Text(src.summary).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)

        if selectedSourceId == src.id {
            Button {
                selectedSourceId = src.id
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                selectedSourceId = src.id
            } label: {
                label
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(seasons) { season in
                        seasonChip(season)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(episodes) { ep in
                        Button {
                            Task { await store.startPlayback(item: ep) }
                        } label: {
                            episodeCard(ep)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private func seasonChip(_ season: VedroMediaItem) -> some View {
        if selectedSeasonId == season.id {
            Button(season.name) {
                selectedSeasonId = season.id
                Task {
                    episodes = await store.fetchEpisodes(seriesId: active.id, seasonId: season.id)
                }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(season.name) {
                selectedSeasonId = season.id
                Task {
                    episodes = await store.fetchEpisodes(seriesId: active.id, seasonId: season.id)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func episodeCard(_ ep: VedroMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(
                url: store.core?.imageURL(itemId: ep.id, type: "Primary", maxWidth: 480, tag: ep.primaryTag)
            ) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(white: 0.16)
                }
            }
            .frame(width: 340, height: 192)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("\(ep.episodeNumber.map { "E\($0) · " } ?? "")\(ep.name)")
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 340, alignment: .leading)
        }
    }
}
