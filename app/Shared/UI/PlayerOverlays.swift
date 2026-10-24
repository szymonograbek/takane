import SwiftUI

/// How far a streak of quick jumps has gone, beside the picture on the side it jumps to ("+30s"),
/// for a moment after each tap.
struct StreakBadge: View {
    let streak: PlayerFeature.StepStreak?
    @State private var shown: PlayerFeature.StepStreak?

    var body: some View {
        // A view that is always there, so the task runs before the first streak.
        Color.clear
            .overlay(alignment: shown?.direction == .forward ? .trailing : .leading) {
                if let shown {
                    VStack(spacing: 8) {
                        Image(systemName: shown.direction == .forward ? "goforward" : "gobackward")
                            .font(.largeTitle)
                        Text(distance(shown)).font(.title3).bold().monospacedDigit()
                    }
                    .foregroundStyle(Palette.text)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.horizontal, Metrics.screenPadding)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown == nil)
            .task(id: streak) {
                shown = streak
                guard streak != nil, (try? await Task.sleep(for: PlayerFeature.streakWindow)) != nil else { return }
                shown = nil
            }
    }

    /// "+30s", "−1m 30s".
    private func distance(_ streak: PlayerFeature.StepStreak) -> String {
        let sign = streak.direction == .forward ? "+" : "−"
        return sign + streak.distance.formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }
}

/// Why the stream cannot play, with a way back to the streams.
struct PlaybackFailure: View {
    let error: PlaybackError
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't Play This Stream", systemImage: "exclamationmark.triangle")
        } description: {
            switch error {
            case .unsupported: Text("Takane can't play this kind of stream. Choose another stream.")
            case .failed(let reason): Text(reason)
            }
        } actions: {
            Button("Choose Another Stream", action: close)
        }
    }
}

/// The spinner for opening or buffering, held back for the first 2 s so a short wait shows only black.
/// Each wait gets a fresh view, so the delay restarts with it.
struct LoadingSpinner: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .opacity(isShown ? 1 : 0)
            .task {
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                isShown = true
            }
    }
}

/// The bare video while the controls are hidden: left and right skip one seek step, anything else shows the controls.
struct RemoteSurface: View {
    @Environment(AppContext.self) private var app
    var focus: FocusState<PlayerFocus?>.Binding
    let interacted: () -> Void
    /// After a skip.
    let stepped: () -> Void

    var body: some View {
        #if os(tvOS)
        // Presses only: a swipe from a resting thumb arrives as a move command and would seek.
        RemotePresses(
            arrow: { isDown, direction in
                if isDown { step(direction) }
            },
            vertical: { _ in interacted() },
            select: interacted
        )
        .focused(focus, equals: .surface)
        #else
        Color.clear
            .contentShape(.rect)
            .focusable()
            .focused(focus, equals: .surface)
            .onTapGesture(perform: interacted)
            .onMoveCommand { direction in
                switch direction {
                case .left: step(.backward)
                case .right: step(.forward)
                case .up, .down: interacted()
                @unknown default: break
                }
            }
        #endif
    }

    private func step(_ direction: PlayerFeature.Direction) {
        app.player.send(.timeline(.step(direction, at: .now)))
        stepped()
    }
}
