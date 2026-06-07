import SwiftUI
import iOSRecorder

/// パススルーウィンドウが「ここだけ触れる」と判定するための共有矩形（ウィンドウ座標）。
final class HitRegionBox: @unchecked Sendable {
    var frame: CGRect = .zero
}

/// 右下に縦並びで常駐する Liquid Glass ボタン群。📷 撮影 / 🐞 メニュー。
struct FloatingButtons: View {
    @Bindable var controller: RecorderController
    var hitRegion: HitRegionBox? = nil
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let center = clusterCenter(in: geo.size)
            // 観測を body の追跡スコープ直下で行い、撮影後のバッジ更新を確実にする
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
            // 非表示中は透明ウィンドウがタッチを奪わないよう、当たり判定を消す。
            if !visible { hitRegion?.frame = .zero }
        }
        .sheet(isPresented: $controller.isPresentingPanel) {
            DebugPanel(controller: controller)
        }
        .task { await controller.refresh() }
    }

    /// クラスタの実フレーム（移動後）をウィンドウへ通知する。
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
