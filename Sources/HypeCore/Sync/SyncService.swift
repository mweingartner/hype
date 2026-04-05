import Foundation

/// Sync status for the UI.
public enum SyncStatus: String, Sendable {
    case disconnected, connecting, connected, error
}

/// Manages collaborative sync state.
public actor SyncService {
    private var status: SyncStatus = .disconnected
    private var roomId: String?
    private var statusListeners: [(SyncStatus) -> Void] = []

    public init() {}

    public func getStatus() -> SyncStatus { status }
    public func getRoomId() -> String? { roomId }

    /// Generate a cryptographically random room ID.
    public func generateRoomId() -> String {
        UUID().uuidString
    }

    /// Connect to a sync room (placeholder for CloudKit implementation).
    public func connect(roomId: String) {
        self.roomId = roomId
        self.status = .connecting
        notifyListeners()

        // In production, this would set up CloudKit subscription
        // For now, simulate connection
        Task {
            try? await Task.sleep(for: .seconds(1))
            await self.completeConnection()
        }
    }

    /// Complete the simulated connection.
    private func completeConnection() {
        self.status = .connected
        notifyListeners()
    }

    /// Disconnect from sync.
    public func disconnect() {
        status = .disconnected
        roomId = nil
        notifyListeners()
    }

    /// Export document for sharing.
    public func exportForSharing(document: HypeDocument) throws -> Data {
        try JSONEncoder().encode(document)
    }

    /// Import a shared document.
    public func importShared(data: Data) throws -> HypeDocument {
        try JSONDecoder().decode(HypeDocument.self, from: data)
    }

    private func notifyListeners() {
        let currentStatus = status
        for listener in statusListeners {
            listener(currentStatus)
        }
    }
}
