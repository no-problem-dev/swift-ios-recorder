import SwiftUI
import iOSRecorder

/// The one rectangle the passthrough window treats as touchable, in window coordinates.
final class HitRegionBox: @unchecked Sendable {
    var frame: CGRect = .zero
}

/// Liquid Glass buttons stacked at the bottom right — 📷 captures, 🐞 opens the panel — draggable anywhere.
struct FloatingButtons: View {
    @Bindable var controller: RecorderController
    var hitRegion: HitRegionBox? = nil
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let center = clusterCenter(in: geo.size)
            // Read the count inside body's tracking scope, or the badge misses the update after a capture
            let badgeCount = controller.summaries.count
            if controller.isOverlayVisible {
                cluster(badgeCount: badgeCount)
                    .background(regionReporter)
                    .position(
                        x: center.x + committedOffset.width + dragOffset.width,
                        y: center.y + committedOffset.height + dragOffset.height
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .updating($dragOffset) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                committedOffset.width += value.translation.width
                                committedOffset.height += value.translation.height
                            }
                    )
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .onChange(of: controller.isOverlayVisible) { _, visible in
            // While hidden, clear the hit region so the transparent window stops stealing touches.
            if !visible { hitRegion?.frame = .zero }
        }
        .sheet(isPresented: $controller.isPresentingPanel) {
            DebugPanel(controller: controller)
        }
        .task { await controller.refresh() }
    }

    /// Reports where the buttons actually sit, drag included, so the window knows which touches to take.
    private var regionReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { hitRegion?.frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                    hitRegion?.frame = newFrame
                }
        }
    }

    private func clusterCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - 48, y: size.height - 116)
    }

    private func cluster(badgeCount: Int) -> some View {
        VStack(spacing: 12) {
            glassCircle(icon: "camera.fill", tint: .blue) {
                Task { @MainActor in await controller.capture() }
            }

            ZStack(alignment: .topTrailing) {
                glassCircle(icon: "ladybug.fill", tint: .indigo) {
                    controller.isPresentingPanel = true
                }
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.red))
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    @ViewBuilder
    private func glassCircle(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        let symbol = Image(systemName: icon).font(.title2).frame(width: 54, height: 54)
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                symbol
                    .foregroundStyle(tint)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                symbol
                    .foregroundStyle(.white)
                    .background(Circle().fill(tint.gradient))
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                    .shadow(radius: 4, y: 2)
            }
        }
        .contentShape(Circle())
        .onTapGesture(perform: action)
    }
}
