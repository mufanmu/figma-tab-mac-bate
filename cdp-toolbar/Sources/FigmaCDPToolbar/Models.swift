import Foundation

struct RGBA: Codable, Equatable, CustomStringConvertible {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        r = try c.decode(Double.self, forKey: .r)
        g = try c.decode(Double.self, forKey: .g)
        b = try c.decode(Double.self, forKey: .b)
        a = try c.decodeIfPresent(Double.self, forKey: .a) ?? 1
    }

    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 1, g: 1, b: 1)

    var description: String {
        String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }

    private enum CodingKeys: String, CodingKey { case r, g, b, a }
}

enum SelectionType: String, Codable, CaseIterable {
    case text = "TEXT"
    case rectangle = "RECTANGLE"
    case frame = "FRAME"
    case group = "GROUP"
    case vector = "VECTOR"
    case ellipse = "ELLIPSE"
    case polygon = "POLYGON"
    case star = "STAR"
    case line = "LINE"
    case component = "COMPONENT"
    case instance = "INSTANCE"
    case section = "SECTION"
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SelectionType(rawValue: raw) ?? .other
    }

    var isShape: Bool {
        switch self {
        case .rectangle, .ellipse, .polygon, .star, .frame,
             .component, .instance, .section: return true
        default: return false
        }
    }
}

struct FontInfo: Codable, Identifiable {
    var id: String { family }
    let family: String
    var styles: [String] = []
}

struct NodeProperties: Codable {
    var id: String = ""
    var name: String = ""
    var type: SelectionType = .other
    var width: Double = 0
    var height: Double = 0
    var x: Double = 0
    var y: Double = 0
    var opacity: Double = 1
    var visible: Bool = true
    var locked: Bool = false

    var cornerRadius: Double?
    var fillColor: RGBA?
    var fillOpacity: Double?
    var strokeColor: RGBA?
    var strokeWeight: Double?

    var fontSize: Double?
    var fontName: String?
    var fontWeight: String?
    var textAlign: String?
    var lineHeight: Double?
    var letterSpacing: Double?
    var paragraphSpacing: Double?
    var paragraphIndent: Double?
    var textDecoration: String?
    var textCase: String?
    var textAutoResize: String?
    var characters: String?

    var selectionCount: Int = 0
    var allTypes: [SelectionType] = []
}

struct ViewportBounds: Codable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}

struct ViewportInfo: Codable {
    var zoom: Double = 1
    var centerX: Double = 0
    var centerY: Double = 0
    var bounds: ViewportBounds?
}

struct CanvasInfo: Codable {
    var left: Double = 0
    var top: Double = 0
    var width: Double = 0
    var height: Double = 0
}

struct FigmaWindowInfo {
    var frame: CGRect = .zero
    var title: String = ""
}
