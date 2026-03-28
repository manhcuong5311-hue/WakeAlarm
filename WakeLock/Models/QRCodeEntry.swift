import Foundation

/// Represents a stored QR code that the user has registered
struct QRCodeEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String        // e.g. "Bathroom", "Kitchen"
    var value: String        // The raw scanned string – stored in Keychain
    var codeType: String     // AVMetadataObject.ObjectType rawValue, e.g. "org.iso.QRCode"
    var createdAt: Date = Date()
    var isPrimary: Bool      // Free tier users can only have one primary

    /// One-word shape hint shown to the user so they know what to look for.
    /// e.g. "Square" for QR, "Circular" for Aztec, "Linear" for 1-D barcodes.
    var shapeHint: String {
        switch codeType {
        case "org.iso.QRCode":           return "Square"
        case "org.iso.Aztec":            return "Circular"
        case "org.iso.DataMatrix":       return "Square"
        case "com.intermec.PDF417":      return "Rectangular"
        default:                         return "Linear"
        }
    }

    /// Human-readable barcode type label
    var typeDisplayName: String {
        switch codeType {
        case "org.iso.QRCode":          return "QR Code"
        case "org.iso.Aztec":           return "Aztec"
        case "org.iso.DataMatrix":      return "Data Matrix"
        case "com.intermec.PDF417":     return "PDF417"
        case "org.gs1.barcode.ean8":    return "EAN-8"
        case "org.gs1.barcode.ean13":   return "EAN-13"
        case "org.gs1.barcode.upce":    return "UPC-E"
        case "org.ansi.aim.code39":     return "Code 39"
        case "com.intermec.code39mod43": return "Code 39+"
        case "com.intermec.code93":     return "Code 93"
        case "org.ansi.aim.code128":    return "Code 128"
        case "org.gs1.barcode.itf14":   return "ITF-14"
        case "org.ansi.aim.2of5":       return "Interleaved 2/5"
        default:                        return "Barcode"
        }
    }

    /// SF Symbol name appropriate for the code type
    var typeIcon: String {
        switch codeType {
        case "org.iso.QRCode", "org.iso.DataMatrix":
            return "qrcode"
        case "org.iso.Aztec":
            return "square.grid.3x3.fill"
        default:
            return "barcode"
        }
    }
}
