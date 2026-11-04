import DayFlowCore
import SwiftUI

/// The day as a dial, like the Mac's: your blocks as teal arcs on an open ring (the gap sits at
/// the bottom), meetings as a thin amber ring outside it, hour marks inside, and a hand for now.
/// The current block is thicker and brighter; finished ones fade. The arcs draw in on first view.
struct DialView: View {
    let blocks: [DayBlock]
    let meetings: [Meeting]
    let now: Date

    // The Mac's geometry, in a 360-point square.
    static let size: CGFloat = 360
    static let rBlock: CGFloat = 132
    static let rMeet: CGFloat = 162
    static let sweep: Double = 300
    static let startAngle: Double = -150

    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var range: (s: Date, e: Date)? {
        let starts = blocks.map(\.start) + meetings.map(\.start)
        let ends = blocks.map(\.end) + meetings.map(\.end)
        guard let s0 = starts.min(), let e0 = ends.max() else { return nil }
        let cal = Calendar.current
        let s = cal.date(bySettingHour: cal.component(.hour, from: s0), minute: 0, second: 0, of: s0)!
        var e = cal.date(bySettingHour: cal.component(.hour, from: e0), minute: 0, second: 0, of: e0)!
        if e < e0 { e = cal.date(byAdding: .hour, value: 1, to: e)! }
        return (s, max(e, s.addingTimeInterval(3600)))
    }

    func angle(_ t: Date, _ r: (s: Date, e: Date)) -> Double {
        Self.startAngle + Self.sweep * min(1, max(0, t.timeIntervalSince(r.s) / r.e.timeIntervalSince(r.s)))
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.size
            ZStack {
                ArcShape(radius: Self.rBlock, from: Self.startAngle, to: Self.startAngle + Self.sweep)
                    .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                if let r = range {
                    ticks(r)
                    // Neighbouring arcs' rounded ends overlap, so finished and upcoming blocks are
                    // each drawn as one layer and faded together, like the Mac's opaque colours.
                    arcs(blocks.filter { now >= $0.end }, r).opacity(0.22)
                    arcs(blocks.filter { now < $0.start }, r).opacity(0.5)
                    // A thin line where one block hands over to the next, so each reads on its own.
                    Path { p in
                        for b in blocks where blocks.contains(where: { $0.end == b.start }) {
                            let a = angle(b.start, r)
                            p.move(to: Self.polar(Self.rBlock - 11, a))
                            p.addLine(to: Self.polar(Self.rBlock + 11, a))
                        }
                    }
                    .stroke(Color(.systemBackground), style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                    .opacity(drawn ? 1 : 0)
                    ForEach(blocks.filter { $0.start <= now && now < $0.end }) { b in
                        arc(b, r)
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                            .shadow(color: Palette.accent.opacity(0.45), radius: 8)
                            .transition(.opacity)
                    }
                    ForEach(meetings) { m in
                        let a0 = angle(m.start, r)
                        ArcShape(radius: Self.rMeet, from: a0, to: max(angle(m.end, r), a0 + 1.5))
                            .trim(from: 0, to: drawn ? 1 : 0)
                            .stroke(Palette.sun, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .animation(.easeOut(duration: 0.65).delay(0.2), value: drawn)
                    }
                    if now >= r.s && now <= r.e {
                        Hand()
                            .rotationEffect(.degrees(angle(now, r)))
                            .animation(.linear(duration: 1), value: now)
                    }
                }
            }
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if reduceMotion { drawn = true } else { withAnimation(.easeOut(duration: 0.65)) { drawn = true } }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    func arc(_ b: DayBlock, _ r: (s: Date, e: Date)) -> some Shape {
        let gap = 3.2 // degrees between neighbouring arcs
        let a0 = angle(b.start, r) + gap / 2
        let a1 = max(angle(b.end, r) - gap / 2, a0 + 0.5)
        return ArcShape(radius: Self.rBlock, from: a0, to: a1).trim(from: 0, to: drawn ? 1 : 0)
    }

    func arcs(_ list: [DayBlock], _ r: (s: Date, e: Date)) -> some View {
        ZStack {
            ForEach(list) { b in
                arc(b, r).stroke(Palette.accent, style: StrokeStyle(lineWidth: 20, lineCap: .round))
            }
        }
        .compositingGroup()
    }

    @ViewBuilder func ticks(_ r: (s: Date, e: Date)) -> some View {
        let hours = Int((r.e.timeIntervalSince(r.s) / 3600).rounded())
        let step = hours > 12 ? 3 : hours > 7 ? 2 : 1
        ForEach(0...hours, id: \.self) { i in
            let t = r.s.addingTimeInterval(Double(i) * 3600)
            let a = angle(t, r)
            let hour = Calendar.current.component(.hour, from: t)
            Path { p in
                p.move(to: Self.polar(Self.rBlock - 22, a))
                p.addLine(to: Self.polar(Self.rBlock - 18, a))
            }
            .stroke(.tertiary, lineWidth: 1.2)
            if hour % step == 0 {
                Text("\(hour % 12 == 0 ? 12 : hour % 12)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .position(Self.polar(Self.rBlock - 33, a))
            }
        }
    }

    static func polar(_ r: CGFloat, _ deg: Double) -> CGPoint {
        let rad = (deg - 90) * .pi / 180
        return CGPoint(x: size / 2 + r * cos(rad), y: size / 2 + r * sin(rad))
    }

    var accessibilitySummary: String {
        guard let cur = blocks.first(where: { $0.start <= now && now < $0.end }) else {
            return "Day dial. \(blocks.count) blocks today."
        }
        return "Day dial. Now: \(cur.title), until \(cur.end.timeText)."
    }

    /// A line from just inside the blocks to just outside the meetings, with a dot at the tip.
    struct Hand: View {
        var body: some View {
            ZStack {
                Path { p in
                    p.move(to: DialView.polar(DialView.rBlock - 14, 0))
                    p.addLine(to: DialView.polar(DialView.rMeet + 8, 0))
                }
                .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(.primary).frame(width: 9, height: 9)
                    .position(DialView.polar(DialView.rMeet + 8, 0))
            }
            .frame(width: DialView.size, height: DialView.size)
        }
    }
}

/// An arc of the dial, from one angle to another (0° is straight up, clockwise).
struct ArcShape: Shape {
    var radius: CGFloat
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}
