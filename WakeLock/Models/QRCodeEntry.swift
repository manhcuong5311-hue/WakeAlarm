import Foundation

/// Represents a stored QR code that the user has registered
struct QRCodeEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String        // e.g. "Bathroom", "Kitchen"
    var value: String        // The raw scanned string – stored in Keychain
    var createdAt: Date = Date()
    var isPrimary: Bool      // Free tier users can only have one primary
}
