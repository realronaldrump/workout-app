import CoreGraphics
import CoreText
import Foundation

nonisolated enum WorkoutPDFError: LocalizedError {
    case cannotCreateDocument
    case cannotLayOutText

    var errorDescription: String? {
        switch self {
        case .cannotCreateDocument: return "The PDF document could not be created."
        case .cannotLayOutText: return "Some report text could not be laid out."
        }
    }
}

nonisolated struct WorkoutPDFAudit {
    var pages = 0
    var setRows = 0
    var workoutHeadings = 0
    var overflowingText = 0
    var outOfBounds = 0
}

nonisolated enum WorkoutPDFStyle {
    static let ink = color(0x243640)
    static let muted = color(0x66767C)
    static let paper = color(0xFAF9F6)
    static let rule = color(0xE2E6E4)
    static let purple = color(0x8670AA)
    static let lilac = color(0xEEEAF5)
    static let green = color(0x4D7E71)
    static let sage = color(0xE8F0EA)
    static let peach = color(0xCB936F)
    static let white = color(0xFFFFFF)
    static let palette = [green, purple, peach, color(0x7194AD), color(0xB5A36C), color(0x9AA5A1)]

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        guard value.isFinite else { return "Unavailable" }
        if abs(value) >= 1_000_000_000 || (value != 0 && abs(value) < 0.001) {
            return String(format: "%.3g", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func count(_ value: Int, _ singular: String) -> String {
        "\(number(Double(value))) \(singular)\(value == 1 ? "" : "s")"
    }
}

/// Core Graphics writes vector pages directly to the atomic file writer, without a full-document bitmap or buffer.
nonisolated final class WorkoutPDFCanvas {
    enum Font: String {
        case regular = "AvenirNext-Regular"
        case medium = "AvenirNext-DemiBold"
        case bold = "AvenirNext-Bold"
        case display = "Georgia"
        case mono = "Menlo-Regular"
    }

    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 42
    static let width: CGFloat = 528
    static let bottom: CGFloat = 730
    let context: CGContext
    private let stream: WorkoutPDFStream
    private let consumer: CGDataConsumer
    private let rangeLabel: String
    private var pageOpen = false
    private var closed = false
    private var fonts: [String: CTFont] = [:]
    private var outline: [[String: Any]] = []
    var audit = WorkoutPDFAudit()
    var cursor: CGFloat = 78
    var section = "Overview"

    init(handle: FileHandle, rangeLabel: String) throws {
        self.rangeLabel = rangeLabel
        stream = WorkoutPDFStream(handle: handle)
        let pointer = Unmanaged.passRetained(stream).toOpaque()
        var callbacks = CGDataConsumerCallbacks(
            putBytes: { info, bytes, count in
                guard let info else { return 0 }
                let stream = Unmanaged<WorkoutPDFStream>.fromOpaque(info).takeUnretainedValue()
                guard stream.error == nil else { return 0 }
                do {
                    try stream.handle.write(contentsOf: Data(bytes: bytes, count: count))
                    return count
                } catch {
                    stream.error = error
                    return 0
                }
            },
            releaseConsumer: { info in
                if let info { Unmanaged<WorkoutPDFStream>.fromOpaque(info).release() }
            }
        )
        guard let consumer = CGDataConsumer(info: pointer, cbks: &callbacks) else {
            Unmanaged<WorkoutPDFStream>.fromOpaque(pointer).release()
            throw WorkoutPDFError.cannotCreateDocument
        }
        self.consumer = consumer
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        let metadata: [String: Any] = [
            kCGPDFContextTitle as String: "Workout report - \(rangeLabel)",
            kCGPDFContextCreator as String: "Big Beautiful Workout",
            kCGPDFContextSubject as String: "Training overview, charts, and selected workout history"
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw WorkoutPDFError.cannotCreateDocument
        }
        self.context = context
    }

    deinit { finish() }

    func newPage(_ section: String? = nil) {
        endPage()
        if let section { self.section = section }
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: Self.pageSize.height)
        context.scaleBy(x: 1, y: -1)
        pageOpen = true
        audit.pages += 1
        fill(CGRect(origin: .zero, size: Self.pageSize), color: WorkoutPDFStyle.paper)
        line(CGPoint(x: 42, y: 56), CGPoint(x: 570, y: 56), color: WorkoutPDFStyle.rule)
        oneLine("BIG BEAUTIFUL WORKOUT", x: 42, y: 30, width: 300, size: 8, font: .bold, color: WorkoutPDFStyle.green)
        oneLine(self.section.uppercased(), x: 390, y: 30, width: 180, size: 8, color: WorkoutPDFStyle.muted, align: .right)
        cursor = 78
    }

    func bookmark(_ title: String) {
        outline.append([kCGPDFOutlineTitle as String: title, kCGPDFOutlineDestination as String: audit.pages])
    }

    func finish() {
        guard !closed else { return }
        endPage()
        CGPDFContextSetOutline(context, [kCGPDFOutlineChildren as String: outline] as CFDictionary)
        context.closePDF()
        closed = true
    }

    func checkWrite() throws { if let error = stream.error { throw error } }

    private func endPage() {
        guard pageOpen else { return }
        line(CGPoint(x: 42, y: 748), CGPoint(x: 570, y: 748), color: WorkoutPDFStyle.rule)
        oneLine(rangeLabel, x: 42, y: 759, width: 420, size: 7.5, color: WorkoutPDFStyle.muted)
        oneLine(String(format: "%02d", audit.pages), x: 526, y: 757, width: 44, size: 9, font: .mono, align: .right)
        context.restoreGState()
        context.endPDFPage()
        pageOpen = false
    }

    func ensureSpace(_ height: CGFloat) { if cursor + height > Self.bottom { newPage() } }

    func fill(_ rect: CGRect, color: CGColor, radius: CGFloat = 0) {
        context.setFillColor(color)
        if radius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        } else { context.fill(rect) }
    }

    func line(_ start: CGPoint, _ end: CGPoint, color: CGColor, width: CGFloat = 0.6) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    func circle(center: CGPoint, radius: CGFloat, color: CGColor) {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func attributes(size: CGFloat, font: Font, color: CGColor) -> [NSAttributedString.Key: Any] {
        let key = "\(font.rawValue)-\(size)"
        let resolved = fonts[key] ?? CTFontCreateWithName(font.rawValue as CFString, size, nil)
        fonts[key] = resolved
        return [NSAttributedString.Key(kCTFontAttributeName as String): resolved,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
    }

    func height(_ text: String, width: CGFloat, size: CGFloat = 10, font: Font = .regular) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: text, attributes: attributes(size: size, font: font, color: WorkoutPDFStyle.ink))
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        ).height) + 3
    }

    func lineWidth(_ text: String, size: CGFloat, font: Font) -> CGFloat {
        let value = NSAttributedString(string: text, attributes: attributes(size: size, font: font, color: WorkoutPDFStyle.ink))
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(value), nil, nil, nil))
    }

    @discardableResult
    func text(
        _ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 10,
        font: Font = .regular, color: CGColor = WorkoutPDFStyle.ink, maxHeight: CGFloat? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let height = min(height(text, width: width, size: size, font: font), maxHeight ?? .greatestFiniteMagnitude)
        let attributed = NSAttributedString(string: text, attributes: attributes(size: size, font: font, color: color))
        let visible = drawText(attributed, in: CGRect(x: x, y: y, width: width, height: height))
        if visible < attributed.length { audit.overflowingText += 1 }
        return height
    }

    /// Single-line truncation is reserved for chart labels; complete names remain in the journal.
    func oneLine(
        _ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 10,
        font: Font = .regular, color: CGColor = WorkoutPDFStyle.ink, align: CTTextAlignment = .left
    ) {
        let attrs = attributes(size: size, font: font, color: color)
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "...", attributes: attrs))
        let line = CTLineCreateTruncatedLine(full, Double(width), .end, token) ?? full
        var ascent: CGFloat = 0
        let measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
        let offset = align == .right ? max(0, width - measured) : align == .center ? max(0, (width - measured) / 2) : 0
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: x + offset, y: y + ascent)
        context.scaleBy(x: 1, y: -1)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    func flowText(_ value: String, size: CGFloat = 10, font: Font = .regular, color: CGColor = WorkoutPDFStyle.ink) throws {
        var remaining = value as NSString
        while remaining.length > 0 {
            ensureSpace(size * 2 + 4)
            let attributed = NSAttributedString(string: remaining as String, attributes: attributes(size: size, font: font, color: color))
            let space = min(Self.bottom - cursor, height(remaining as String, width: Self.width, size: size, font: font))
            let visible = drawText(attributed, in: CGRect(x: Self.margin, y: cursor, width: Self.width, height: space))
            guard visible > 0 else { throw WorkoutPDFError.cannotLayOutText }
            remaining = remaining.substring(from: visible) as NSString
            cursor += space
            if remaining.length > 0 { newPage() }
        }
    }

    private func drawText(_ attributed: NSAttributedString, in rect: CGRect) -> Int {
        if rect.minY < 0 || rect.maxY > Self.pageSize.height || rect.minX < 0 || rect.maxX > Self.pageSize.width { audit.outOfBounds += 1 }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
        return CTFrameGetVisibleStringRange(frame).length
    }
}

private nonisolated final class WorkoutPDFStream {
    let handle: FileHandle
    var error: Error?
    init(handle: FileHandle) { self.handle = handle }
}
