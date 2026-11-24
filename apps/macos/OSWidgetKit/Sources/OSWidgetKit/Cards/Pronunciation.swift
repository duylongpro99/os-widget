import AVFoundation
import Foundation
import os

/// What a pronounce button plays.
public enum PronunciationSource: Sendable, Hashable {
    /// The item's `audio_url`, already accepted by `URLPolicy.loadableURL`.
    case audio(URL)
    /// The word, read by the system speech synthesizer.
    case speech(String)

    /// The audio file when `audioURL` may be loaded (`https` with a host), else the spoken word.
    public static func choose(word: String, audioURL: String?) -> PronunciationSource {
        URLPolicy.loadableURL(audioURL).map(PronunciationSource.audio) ?? .speech(word)
    }
}

/// What happens to an audio file after `AudioPlayback.play` started it.
public enum AudioPlaybackEvent: Sendable, Hashable {
    /// The file loaded and is playing.
    case started
    /// The file could not be loaded or played. `reason` is a short code for the log.
    case failed(reason: String)
}

/// Plays one audio file at a time. `play` replaces whatever was playing.
@MainActor
public protocol AudioPlayback: AnyObject {
    func play(_ url: URL, onEvent: @escaping @MainActor (AudioPlaybackEvent) -> Void)
    func stop()
}

/// Reads one word at a time. `speak` replaces whatever was being read.
@MainActor
public protocol SpeechPlayback: AnyObject {
    func speak(_ word: String)
    func stop()
}

/// Plays the pronunciation of a word when the user asks for it, never on its own (FR-7).
///
/// An `audio_url` is played when `URLPolicy` allows loading it. When it cannot be loaded, fails while
/// playing, or has not started within `audioTimeout`, the word is read by the speech synthesizer instead.
/// Asking again while something plays stops it and starts from the beginning.
@MainActor
public final class Pronouncer {
    public static let shared = Pronouncer(audio: SystemAudioPlayback(), speech: SystemSpeechPlayback())

    private static let log = Logger(subsystem: "local.oswidget.app", category: "audio")

    private let audio: AudioPlayback
    private let speech: SpeechPlayback
    private let audioTimeout: Duration
    /// Counts requests, so events and timeouts of a replaced request are ignored.
    private var generation = 0
    private var timeout: Task<Void, Never>?

    public init(audio: AudioPlayback, speech: SpeechPlayback, audioTimeout: Duration = .seconds(5)) {
        self.audio = audio
        self.speech = speech
        self.audioTimeout = audioTimeout
    }

    public func pronounce(word: String, audioURL: String?) {
        stop()
        generation += 1
        let request = generation
        switch PronunciationSource.choose(word: word, audioURL: audioURL) {
        case .speech(let word):
            Self.log.info("pronounce.play source=speech")
            speech.speak(word)
        case .audio(let url):
            Self.log.info("pronounce.play source=audio")
            timeout = Task { [audioTimeout] in
                try? await Task.sleep(for: audioTimeout)
                guard !Task.isCancelled else { return }
                self.fallBack(request: request, word: word, reason: "timeout")
            }
            audio.play(url) { [weak self] event in
                self?.handle(event, request: request, word: word)
            }
        }
    }

    public func stop() {
        generation += 1
        timeout?.cancel()
        timeout = nil
        audio.stop()
        speech.stop()
    }

    private func handle(_ event: AudioPlaybackEvent, request: Int, word: String) {
        guard request == generation else { return }
        switch event {
        case .started:
            timeout?.cancel()
            timeout = nil
        case .failed(let reason):
            fallBack(request: request, word: word, reason: reason)
        }
    }

    private func fallBack(request: Int, word: String, reason: String) {
        guard request == generation else { return }
        // A new generation, so a late event of the abandoned audio does not read the word again.
        generation += 1
        timeout?.cancel()
        timeout = nil
        audio.stop()
        Self.log.info("pronounce.fallback reason=\(reason, privacy: .public)")
        speech.speak(word)
    }
}

/// `AudioPlayback` with `AVPlayer`. The player is released when the file ends, fails or is stopped.
@MainActor
final class SystemAudioPlayback: AudioPlayback {
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?

    func play(_ url: URL, onEvent: @escaping @MainActor (AudioPlaybackEvent) -> Void) {
        stop()
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            let status = item.status
            Task { @MainActor in
                switch status {
                case .readyToPlay: onEvent(.started)
                case .failed: onEvent(.failed(reason: "load"))
                default: break
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { _ in
            Task { @MainActor in onEvent(.failed(reason: "play")) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Only when this file is still the current one; a newer `play` owns the player now.
                if self?.player?.currentItem === item { self?.stop() }
            }
        }
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
    }

    func stop() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

/// `SpeechPlayback` with `AVSpeechSynthesizer`, in American English when that voice is installed and in
/// the system's default voice otherwise.
@MainActor
final class SystemSpeechPlayback: SpeechPlayback {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ word: String) {
        stop()
        let utterance = AVSpeechUtterance(string: word)
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
