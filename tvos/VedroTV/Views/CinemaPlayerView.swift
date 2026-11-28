import AVFoundation
import AVKit
import SwiftUI

/// Native Apple TV cinema player backed by AVPlayerViewController:
/// - Automatically engages Apple TV OS-licensed Dolby Vision / HDR10 / Match Frame Rate
///   and multichannel Spatial Audio / Dolby Atmos (E-AC-3 JOC) via AVAudioSession.
/// - Streams directly through Vedro's Rust StreamProxy (302 redirect caching + Range prefetch)
///   and synchronizes playback progress back to Emby / Jellyfin / EmbyGo every 10s.
struct CinemaPlayerView: View {
    @EnvironmentObject private var store: VedroTVStore
    @Environment(\.dismiss) private var dismiss
    let playback: VedroPreparedPlayback

    @State private var playerError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            AVPlayerViewControllerWrapper(
                playback: playback,
                onStart: { pos in store.reportPlaybackStart(playback, positionSecs: pos) },
                onProgress: { pos, paused in store.reportPlaybackProgress(playback, positionSecs: pos, isPaused: paused) },
                onStop: { pos in store.reportPlaybackStopped(playback, positionSecs: pos) },
                onError: { msg in playerError = msg }
            )
            .ignoresSafeArea()

            if let playerError {
                VStack(spacing: 18) {
                    Text("播放失败")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(playerError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                    Button("返回") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct AVPlayerViewControllerWrapper: UIViewControllerRepresentable {
    let playback: VedroPreparedPlayback
    let onStart: (Double) -> Void
    let onProgress: (Double, Bool) -> Void
    let onStop: (Double) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playback: playback,
            onStart: onStart,
            onProgress: onProgress,
            onStop: onStop,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        configureAudioSession()

        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.appliesPreferredDisplayCriteriaAutomatically = true

        let asset = AVURLAsset(url: playback.proxyUrl)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 15.0

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.appliesMediaSelectionCriteriaAutomatically = true
        controller.player = player

        context.coordinator.attach(player: player, item: item)

        if playback.startSeconds > 3.0 {
            let target = CMTime(seconds: playback.startSeconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
            }
        } else {
            player.play()
        }
        onStart(playback.startSeconds)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.detach()
        uiViewController.player?.pause()
        uiViewController.player = nil
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            if #available(tvOS 15.0, *) {
                try? session.setSupportsMultichannelContent(true)
            }
            try session.setActive(true)
        } catch {}
    }

    final class Coordinator: NSObject {
        private let playback: VedroPreparedPlayback
        private let onStart: (Double) -> Void
        private let onProgress: (Double, Bool) -> Void
        private let onStop: (Double) -> Void
        private let onError: (String) -> Void

        private weak var player: AVPlayer?
        private var timeObserver: Any?
        private var statusObservation: NSKeyValueObservation?
        private var lastReportedSecs: Double = 0

        init(
            playback: VedroPreparedPlayback,
            onStart: @escaping (Double) -> Void,
            onProgress: @escaping (Double, Bool) -> Void,
            onStop: @escaping (Double) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.playback = playback
            self.onStart = onStart
            self.onProgress = onProgress
            self.onStop = onStop
            self.onError = onError
        }

        func attach(player: AVPlayer, item: AVPlayerItem) {
            self.player = player
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard let self else { return }
                if observed.status == .failed {
                    let detail = observed.error?.localizedDescription ?? "AVPlayer 无法解析该封装格式（如 MKV 需服务端提供 HLS 或 MP4 片源）"
                    DispatchQueue.main.async {
                        self.onError(detail)
                    }
                }
            }
            let interval = CMTime(seconds: 10.0, preferredTimescale: 1)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                guard let self, let player else { return }
                let secs = time.seconds.isFinite ? max(0, time.seconds) : 0
                self.lastReportedSecs = secs
                self.onProgress(secs, player.timeControlStatus != .playing)
            }
        }

        func detach() {
            if let player, let obs = timeObserver {
                player.removeTimeObserver(obs)
                timeObserver = nil
            }
            statusObservation?.invalidate()
            statusObservation = nil
            let current = player?.currentTime().seconds ?? lastReportedSecs
            let safeSecs = current.isFinite ? max(0, current) : lastReportedSecs
            onStop(safeSecs)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
