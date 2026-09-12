import CompanionCore
import SwiftUI
import UIKit

struct DockMessage: Identifiable, Equatable {
    var id: String
    var text: String
}

struct EdgeDock: View {
    let messages: [DockMessage]
    let todos: [PlanItem]
    var onJump: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var tab = 0
    @State private var x: CGFloat = -1
    @State private var y: CGFloat = 12
    @State private var origin = CGSize.zero

    private let orb: CGFloat = 36
    private let pad: CGFloat = 12
    private let panelWidth: CGFloat = 280

    @State private var container = CGSize.zero

    var body: some View {
        let size = container
        let orbX = placedX(in: size.width)
        let orbY = placedY(in: size.height)
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _, newSize in
                    let first = container == .zero
                    container = newSize
                    if first, x < 0 { x = newSize.width - pad - orb }
                    else if !first { snap(in: newSize, animated: false) }
                }
            if open {
                panel
                    .offset(x: panelX(orbX: orbX, width: size.width), y: orbY)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }
            orbButton
                .offset(x: orbX, y: orbY)
                .gesture(drag(in: size))
        }
        .animation(reduceMotion ? Theme.Motion.chrome : .spring(response: 0.4, dampingFraction: 1), value: open)
    }

    private var orbButton: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(active ? Theme.accent.opacity(0.85) : Theme.textPrimary.opacity(0.72))
            .frame(width: orb, height: orb)
            .background(Theme.bgElevated, in: Circle())
            .hairlineBorder(orb / 2)
            .accessibilityLabel("导航")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("消息列表与任务列表")
    }

    private var active: Bool { open || !messages.isEmpty || !todos.isEmpty }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                dockTab("消息列表", index: 0)
                dockTab("任务列表", index: 1)
            }
            .padding(3)
            .background(Theme.codeSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if tab == 0 {
                messageList
            } else {
                todoList
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: panelWidth, alignment: .leading)
        .frame(maxHeight: 420, alignment: .top)
        .background(Theme.bgElevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .hairlineBorder(18)
    }

    private func dockTab(_ title: String, index: Int) -> some View {
        Button {
            tab = index
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tab == index ? Theme.onAccent : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(tab == index ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text("还没有用户消息")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(8)
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, item in
                    Button {
                        open = false
                        onJump(item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.codeSurface, in: Capsule())
                            Text(item.text.isEmpty ? "消息" : item.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.bg.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var todoList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if todos.isEmpty {
                    Text("还没有任务")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(8)
                }
                ForEach(todos) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : (item.isActive ? "circle.lefthalf.filled" : "circle"))
                            .font(.body)
                            .foregroundStyle(item.isDone ? Theme.pass : (item.isActive ? Theme.accent : Theme.textTertiary))
                        Text(item.content)
                            .font(.subheadline)
                            .foregroundStyle(item.isDone ? Theme.textTertiary : Theme.textPrimary)
                            .strikethrough(item.isDone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if origin == .zero {
                    origin = CGSize(width: placedX(in: size.width), height: placedY(in: size.height))
                }
                let nextX = origin.width + value.translation.width
                let nextY = origin.height + value.translation.height
                x = rubber(nextX, min: pad, max: size.width - orb - pad, dimension: size.width)
                y = rubber(nextY, min: pad, max: size.height - orb - pad, dimension: size.height)
            }
            .onEnded { value in
                let traveled = hypot(value.translation.width, value.translation.height)
                origin = .zero
                if traveled < 10 {
                    open.toggle()
                    if open { tab = 0 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    return
                }
                snap(in: size, animated: true)
            }
    }

    private func snap(in size: CGSize, animated: Bool) {
        let left = x + orb / 2 < size.width / 2
        let tx = left ? pad : max(pad, size.width - orb - pad)
        let ty = min(max(y, pad), max(pad, size.height - orb - pad))
        let apply = {
            x = tx
            y = ty
        }
        if animated, !reduceMotion {
            withAnimation(.spring(response: 0.4, dampingFraction: 1)) { apply() }
        } else if animated {
            withAnimation(.easeOut(duration: 0.2)) { apply() }
        } else {
            apply()
        }
    }

    private func placedX(in width: CGFloat) -> CGFloat {
        if x < 0 { return max(pad, width - pad - orb) }
        return x
    }

    private func placedY(in height: CGFloat) -> CGFloat {
        min(max(y, pad), max(pad, height - orb - pad))
    }

    private func panelX(orbX: CGFloat, width: CGFloat) -> CGFloat {
        let onLeft = orbX + orb / 2 <= width / 2
        if onLeft {
            return min(orbX + orb + 8, width - panelWidth - pad)
        }
        return max(pad, orbX - panelWidth - 8)
    }

    private func rubber(_ value: CGFloat, min: CGFloat, max: CGFloat, dimension: CGFloat) -> CGFloat {
        if value < min {
            let over = min - value
            return min - (over * dimension * 0.55) / (dimension + 0.55 * abs(over))
        }
        if value > max {
            let over = value - max
            return max + (over * dimension * 0.55) / (dimension + 0.55 * abs(over))
        }
        return value
    }
}
