import Foundation
import Combine

/// Keys used in Keychain / UserDefaults
private enum StorageKey {
    static let qrEntries = "wakelock.qr.entries"
}

/// Manages stored QR codes.  Values are persisted to Keychain; metadata to UserDefaults.
final class QRManager: ObservableObject {

    static let shared = QRManager()
    private init() { load() }

    @Published private(set) var entries: [QRCodeEntry] = []

    /// Free tier allows only 1 QR code
    var isPremium: Bool {
        UserDefaults.standard.bool(forKey: "wakelock.premium")
    }

    var canAddMore: Bool {
        isPremium || entries.isEmpty
    }

    var hasQR: Bool { !entries.isEmpty }

    // MARK: - CRUD

    func add(label: String, value: String) {
        guard canAddMore else { return }
        var entry = QRCodeEntry(label: label, value: value, isPrimary: entries.isEmpty)
        // Persist the raw QR value securely in Keychain
        KeychainService.shared.save(value, forKey: keychainKey(for: entry.id))
        entries.append(entry)
        saveMetadata()
    }

    func delete(_ entry: QRCodeEntry) {
        KeychainService.shared.delete(forKey: keychainKey(for: entry.id))
        entries.removeAll { $0.id == entry.id }
        // Promote next entry to primary if needed
        if !entries.isEmpty && !entries.contains(where: { $0.isPrimary }) {
            entries[0].isPrimary = true
        }
        saveMetadata()
    }

    /// Rename a QR entry's label without changing its scanned value.
    func updateLabel(_ entry: QRCodeEntry, label: String) {
        guard let idx = entries.firstIndex(of: entry) else { return }
        entries[idx].label = label
        saveMetadata()
    }

    /// Replace the raw QR value of an existing entry (user re-scanned).
    func rescan(_ entry: QRCodeEntry, newValue: String) {
        guard let idx = entries.firstIndex(of: entry) else { return }
        KeychainService.shared.delete(forKey: keychainKey(for: entry.id))
        KeychainService.shared.save(newValue, forKey: keychainKey(for: entry.id))
        entries[idx].value = newValue
        saveMetadata()
    }

    func setPrimary(_ entry: QRCodeEntry) {
        for i in entries.indices { entries[i].isPrimary = false }
        if let idx = entries.firstIndex(of: entry) { entries[idx].isPrimary = true }
        saveMetadata()
    }

    /// Validate a scanned string against stored QR entries
    /// Returns the matching entry label if found
    func validate(scanned: String) -> String? {
        for entry in entries {
            let stored = KeychainService.shared.load(forKey: keychainKey(for: entry.id))
            if stored == scanned { return entry.label }
        }
        return nil
    }

    /// Pick a random QR entry (premium feature)
    func randomEntry() -> QRCodeEntry? { entries.randomElement() }

    // MARK: - Persistence

    private func keychainKey(for id: UUID) -> String { "qr.\(id.uuidString)" }

    private func saveMetadata() {
        // Store only metadata (no raw values) in UserDefaults
        let metadata = entries.map { e -> [String: String] in
            ["id": e.id.uuidString,
             "label": e.label,
             "isPrimary": e.isPrimary ? "1" : "0",
             "createdAt": ISO8601DateFormatter().string(from: e.createdAt)]
        }
        UserDefaults.standard.set(metadata, forKey: StorageKey.qrEntries)
    }

    private func load() {
        guard let metadata = UserDefaults.standard.array(forKey: StorageKey.qrEntries)
                as? [[String: String]] else { return }
        entries = metadata.compactMap { dict -> QRCodeEntry? in
            guard let idStr = dict["id"],
                  let id = UUID(uuidString: idStr),
                  let label = dict["label"] else { return nil }
            // Re-fetch raw value from keychain
            guard let value = KeychainService.shared.load(forKey: "qr.\(idStr)") else { return nil }
            let isPrimary = dict["isPrimary"] == "1"
            let createdAt = dict["createdAt"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            var entry = QRCodeEntry(label: label, value: value, isPrimary: isPrimary)
            entry.id = id
            entry.createdAt = createdAt
            return entry
        }
    }
}
