import Foundation

/// Writes CAML (Core Animation Markup Language) in the dialect found in real
/// community wallpapers (CAPlayground output): <CALayer> elements with
/// `bounds`/`position` attributes, `<contents><CGImage src=…/>`, and
/// `<animation type="CAKeyframeAnimation" …><values>…</values></animation>`.
/// Only constructs seen in validated real files are emitted.
enum CAMLWriter {
    static let namespace = "http://www.apple.com/CoreAnimation/1.0"

    static func num(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e9 { return String(Int64(v)) }
        var s = String(format: "%.5f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func esc(_ s: String) -> String {
        var o = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            case "\n", "\r", "\t": o += " "
            default:
                // Drop characters illegal in XML 1.0.
                if c.value >= 0x20 && c.value != 0xFFFE && c.value != 0xFFFF { o.unicodeScalars.append(c) }
            }
        }
        return o
    }

    /// Standard empty state machine copied from the real Foreground template.
    private static let statesXML = """
        <modules/>
        <states>
          <LKState name="Locked"><elements/></LKState>
          <LKState name="Unlock"><elements/></LKState>
          <LKState name="Sleep"><elements/></LKState>
        </states>
        <stateTransitions>
          <LKStateTransition fromState="*" toState="Unlock"><elements/></LKStateTransition>
          <LKStateTransition fromState="Unlock" toState="*"><elements/></LKStateTransition>
          <LKStateTransition fromState="*" toState="Locked"><elements/></LKStateTransition>
          <LKStateTransition fromState="Locked" toState="*"><elements/></LKStateTransition>
          <LKStateTransition fromState="*" toState="Sleep"><elements/></LKStateTransition>
          <LKStateTransition fromState="Sleep" toState="*"><elements/></LKStateTransition>
        </stateTransitions>
    """

    static func document(canvas: CGSize, backgroundColor: RGBA?, layers: [ResolvedLayer],
                         assetPath: (String) -> String) -> String {
        let w = num(canvas.width), h = num(canvas.height)
        let cx = num(canvas.width / 2), cy = num(canvas.height / 2)
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        x += "<caml xmlns=\"\(namespace)\">\n"
        x += "  <CALayer id=\"__capRootLayer__\" name=\"TendieStudio Root\" bounds=\"0 0 \(w) \(h)\" position=\"\(cx) \(cy)\" zPosition=\"0\" geometryFlipped=\"0\" opacity=\"1\" allowsEdgeAntialiasing=\"1\" allowsGroupOpacity=\"1\" contentsFormat=\"RGBA8\" cornerCurve=\"circular\">\n"
        x += "    <sublayers>\n"
        x += "      <CALayer id=\"root\" name=\"Root Layer\" bounds=\"0 0 \(w) \(h)\" position=\"\(cx) \(cy)\" zPosition=\"0\" geometryFlipped=\"0\" opacity=\"1\" allowsEdgeAntialiasing=\"1\" allowsGroupOpacity=\"1\" contentsFormat=\"RGBA8\" cornerCurve=\"circular\">\n"
        x += "        <sublayers>\n"
        if let bg = backgroundColor {
            x += "          <CALayer id=\"bgcolor\" name=\"Background Color\" bounds=\"0 0 \(w) \(h)\" position=\"\(cx) \(cy)\" zPosition=\"0\" opacity=\"1\" backgroundColor=\"\(color(bg))\" allowsEdgeAntialiasing=\"1\" allowsGroupOpacity=\"1\" contentsFormat=\"RGBA8\" cornerCurve=\"circular\"/>\n"
        }
        for (i, l) in layers.enumerated() { x += layerXML(l, index: i, assetPath: assetPath) }
        x += "        </sublayers>\n      </CALayer>\n    </sublayers>\n"
        x += statesXML + "\n"
        x += "  </CALayer>\n</caml>\n"
        return x
    }

    static func color(_ c: RGBA) -> String { "\(num(c.r)) \(num(c.g)) \(num(c.b))" }

    static func layerXML(_ l: ResolvedLayer, index: Int, assetPath: (String) -> String) -> String {
        let deg = num(l.rotationRadians * 180 / .pi)
        var a = "id=\"L\(index + 1)_\(l.id.uuidString.prefix(8))\" name=\"\(esc(l.name))\""
        a += " bounds=\"0 0 \(num(l.bounds.width)) \(num(l.bounds.height))\""
        a += " position=\"\(num(l.position.x)) \(num(l.position.y))\" zPosition=\"0\""
        a += " opacity=\"\(num(l.opacity))\""
        a += " transform.rotation.z=\"\(num(l.rotationRadians))\" transform.rotation.x=\"0\" transform.rotation.y=\"0\""
        a += " transform=\"rotate(\(deg)deg) rotate(0deg, 0, 1, 0) rotate(0deg, 1, 0, 0)\""
        if l.kind != .image { a += " backgroundColor=\"\(color(l.fill))\"" }
        a += " cornerRadius=\"\(num(l.cornerRadius))\""
        a += " allowsEdgeAntialiasing=\"1\" allowsGroupOpacity=\"1\" contentsFormat=\"RGBA8\" cornerCurve=\"circular\""
        let hasContent = l.kind == .image && l.assetName != nil
        if !hasContent && l.animations.isEmpty { return "          <CALayer \(a)/>\n" }
        var x = "          <CALayer \(a)>\n"
        if hasContent, let n = l.assetName {
            x += "            <contents>\n              <CGImage src=\"\(esc(assetPath(n)))\"/>\n            </contents>\n"
        }
        if !l.animations.isEmpty {
            x += "            <animations>\n"
            for (i, an) in l.animations.enumerated() {
                x += "              <animation key=\"animation-\(i)\" type=\"CAKeyframeAnimation\" keyPath=\"\(an.keyPath)\""
                x += " autoreverses=\"\(an.autoreverses ? 1 : 0)\" beginTime=\"1e-100\" duration=\"\(num(an.duration))\""
                x += " speed=\"1\" removedOnCompletion=\"0\" repeatCount=\"inf\" repeatDuration=\"inf\" calculationMode=\"linear\">\n"
                x += "                <values>\n"
                for v in an.values {
                    switch an.kind {
                    case .point: x += "                  <CGPoint value=\"\(num(v[0])) \(num(v[1]))\"/>\n"
                    case .real: x += "                  <real value=\"\(num(v[0]))\"/>\n"
                    }
                }
                x += "                </values>\n              </animation>\n"
            }
            x += "            </animations>\n"
        }
        x += "          </CALayer>\n"
        return x
    }
}
