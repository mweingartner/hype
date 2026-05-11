import Foundation

/// Sync status for the UI.
public enum SyncStatus: String, Sendable, Codable {
    case disconnected, connecting, connected, error
}

/// Stable peer identity for a live sync participant.
public struct SyncPeer: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String

    public init(id: String = UUID().uuidString, displayName: String = Host.current().localizedName ?? "Hype") {
        self.id = id
        self.displayName = displayName
    }
}

/// Supported document operations for transport-neutral live sync.
public enum SyncOperationKind: String, Sendable, Codable {
    case replaceDocument
    case updateStack
    case upsertBackground
    case deleteBackground
    case upsertCard
    case deleteCard
    case upsertPart
    case deletePart
    case setPaintLayer
    case removePaintLayer
}

/// A single sync operation. It is intentionally Codable so a CloudKit,
/// Multipeer, or server transport can ship the same payload later.
public struct SyncOperation: Sendable, Codable, Identifiable {
    public var id: UUID
    public var peerId: String
    public var baseRevision: Int
    public var createdAt: Date
    public var kind: SyncOperationKind

    public var document: HypeDocument?
    public var stack: Stack?
    public var background: Background?
    public var backgroundId: UUID?
    public var card: Card?
    public var cardId: UUID?
    public var part: Part?
    public var partId: UUID?
    public var paintLayer: CardPaintLayer?
    public var paintLayerCardId: UUID?

    public init(
        id: UUID = UUID(),
        peerId: String,
        baseRevision: Int,
        createdAt: Date = Date(),
        kind: SyncOperationKind,
        document: HypeDocument? = nil,
        stack: Stack? = nil,
        background: Background? = nil,
        backgroundId: UUID? = nil,
        card: Card? = nil,
        cardId: UUID? = nil,
        part: Part? = nil,
        partId: UUID? = nil,
        paintLayer: CardPaintLayer? = nil,
        paintLayerCardId: UUID? = nil
    ) {
        self.id = id
        self.peerId = peerId
        self.baseRevision = baseRevision
        self.createdAt = createdAt
        self.kind = kind
        self.document = document
        self.stack = stack
        self.background = background
        self.backgroundId = backgroundId
        self.card = card
        self.cardId = cardId
        self.part = part
        self.partId = partId
        self.paintLayer = paintLayer
        self.paintLayerCardId = paintLayerCardId
    }

    public var touchedEntityKey: String {
        switch kind {
        case .replaceDocument:
            return "document"
        case .updateStack:
            return "stack:\(stack?.id.uuidString ?? "current")"
        case .upsertBackground:
            return "background:\(background?.id.uuidString ?? backgroundId?.uuidString ?? "unknown")"
        case .deleteBackground:
            return "background:\(backgroundId?.uuidString ?? "unknown")"
        case .upsertCard:
            return "card:\(card?.id.uuidString ?? cardId?.uuidString ?? "unknown")"
        case .deleteCard:
            return "card:\(cardId?.uuidString ?? "unknown")"
        case .upsertPart:
            return "part:\(part?.id.uuidString ?? partId?.uuidString ?? "unknown")"
        case .deletePart:
            return "part:\(partId?.uuidString ?? "unknown")"
        case .setPaintLayer:
            return "paint:\(paintLayer?.cardId.uuidString ?? paintLayerCardId?.uuidString ?? "unknown")"
        case .removePaintLayer:
            return "paint:\(paintLayerCardId?.uuidString ?? "unknown")"
        }
    }
}

/// A batch of sync operations that should be applied in order.
public struct SyncChangeSet: Sendable, Codable {
    public var id: UUID
    public var baseRevision: Int
    public var operations: [SyncOperation]

    public init(id: UUID = UUID(), baseRevision: Int, operations: [SyncOperation]) {
        self.id = id
        self.baseRevision = baseRevision
        self.operations = operations
    }
}

/// Deterministic conflict surfaced when a stale operation touches an entity
/// changed by another peer after the operation's base revision.
public struct SyncConflict: Sendable, Codable, Equatable {
    public var operationId: UUID
    public var entityKey: String
    public var localBaseRevision: Int
    public var remoteRevision: Int
    public var reason: String

    public init(operationId: UUID, entityKey: String, localBaseRevision: Int, remoteRevision: Int, reason: String) {
        self.operationId = operationId
        self.entityKey = entityKey
        self.localBaseRevision = localBaseRevision
        self.remoteRevision = remoteRevision
        self.reason = reason
    }
}

/// Snapshot returned to peers after publish/pull.
public struct SyncCheckpoint: Sendable, Codable {
    public var roomId: String
    public var revision: Int
    public var document: HypeDocument?
    public var operations: [SyncOperation]

    public init(roomId: String, revision: Int, document: HypeDocument?, operations: [SyncOperation]) {
        self.roomId = roomId
        self.revision = revision
        self.document = document
        self.operations = operations
    }
}

public struct SyncPublishResult: Sendable, Codable {
    public var accepted: Bool
    public var revision: Int
    public var document: HypeDocument?
    public var conflicts: [SyncConflict]
    public var appliedOperationIds: [UUID]

    public init(accepted: Bool, revision: Int, document: HypeDocument?, conflicts: [SyncConflict], appliedOperationIds: [UUID]) {
        self.accepted = accepted
        self.revision = revision
        self.document = document
        self.conflicts = conflicts
        self.appliedOperationIds = appliedOperationIds
    }
}

private actor InMemorySyncHub {
    struct Room {
        var document: HypeDocument?
        var revision: Int = 0
        var operations: [SyncOperation] = []
        var peers: [String: SyncPeer] = [:]
    }

    private var rooms: [String: Room] = [:]

    func join(roomId: String, peer: SyncPeer, initialDocument: HypeDocument?) -> SyncCheckpoint {
        var room = rooms[roomId] ?? Room()
        room.peers[peer.id] = peer
        if room.document == nil, let initialDocument {
            room.document = initialDocument
        }
        rooms[roomId] = room
        return SyncCheckpoint(roomId: roomId, revision: room.revision, document: room.document, operations: room.operations)
    }

    func leave(roomId: String, peerId: String) {
        guard var room = rooms[roomId] else { return }
        room.peers.removeValue(forKey: peerId)
        rooms[roomId] = room
    }

    func checkpoint(roomId: String, afterRevision revision: Int = 0) -> SyncCheckpoint? {
        guard let room = rooms[roomId] else { return nil }
        return SyncCheckpoint(
            roomId: roomId,
            revision: room.revision,
            document: room.document,
            operations: room.operations.filter { $0.baseRevision >= revision }
        )
    }

    func publish(roomId: String, changeSet: SyncChangeSet) -> SyncPublishResult {
        var room = rooms[roomId] ?? Room()
        var document = room.document
        var conflicts: [SyncConflict] = []
        var applied: [UUID] = []

        for operation in changeSet.operations {
            if let conflict = conflictFor(operation: operation, in: room) {
                conflicts.append(conflict)
                continue
            }

            var working = document ?? operation.document ?? HypeDocument.newDocument()
            apply(operation, to: &working)
            document = working
            room.revision += 1
            room.operations.append(operation)
            applied.append(operation.id)
        }

        room.document = document
        rooms[roomId] = room
        return SyncPublishResult(
            accepted: conflicts.isEmpty,
            revision: room.revision,
            document: document,
            conflicts: conflicts,
            appliedOperationIds: applied
        )
    }

    private func conflictFor(operation: SyncOperation, in room: Room) -> SyncConflict? {
        guard operation.baseRevision < room.revision else { return nil }
        let entity = operation.touchedEntityKey
        let changedSinceBase = room.operations.contains { prior in
            prior.baseRevision >= operation.baseRevision && prior.touchedEntityKey == entity && prior.peerId != operation.peerId
        }
        guard changedSinceBase || operation.kind == .replaceDocument else { return nil }
        return SyncConflict(
            operationId: operation.id,
            entityKey: entity,
            localBaseRevision: operation.baseRevision,
            remoteRevision: room.revision,
            reason: "Remote changes touched \(entity) after revision \(operation.baseRevision)."
        )
    }

    private func apply(_ operation: SyncOperation, to document: inout HypeDocument) {
        switch operation.kind {
        case .replaceDocument:
            if let replacement = operation.document {
                document = replacement
            }
        case .updateStack:
            if let stack = operation.stack {
                document.stack = stack
            }
        case .upsertBackground:
            guard let background = operation.background else { return }
            if let index = document.backgrounds.firstIndex(where: { $0.id == background.id }) {
                document.backgrounds[index] = background
            } else {
                document.backgrounds.append(background)
            }
        case .deleteBackground:
            guard let id = operation.backgroundId else { return }
            document.backgrounds.removeAll { $0.id == id }
            document.parts.removeAll { $0.backgroundId == id }
            document.cards.removeAll { $0.backgroundId == id }
        case .upsertCard:
            guard let card = operation.card else { return }
            if let index = document.cards.firstIndex(where: { $0.id == card.id }) {
                document.cards[index] = card
            } else {
                document.cards.append(card)
            }
        case .deleteCard:
            guard let id = operation.cardId else { return }
            document.cards.removeAll { $0.id == id }
            document.parts.removeAll { $0.cardId == id }
            document.removePaintLayer(forCardId: id)
        case .upsertPart:
            guard let part = operation.part else { return }
            if let index = document.partIndex(byId: part.id) {
                document.parts[index] = part
            } else {
                document.parts.append(part)
            }
        case .deletePart:
            guard let id = operation.partId else { return }
            document.removePart(id: id)
        case .setPaintLayer:
            guard let layer = operation.paintLayer else { return }
            document.setPaintLayer(layer)
        case .removePaintLayer:
            guard let cardId = operation.paintLayerCardId else { return }
            document.removePaintLayer(forCardId: cardId)
        }
    }
}

/// Manages collaborative sync state. The default transport is an in-process
/// hub that gives deterministic live-sync semantics for tests and local app
/// windows; a CloudKit/Multipeer/server transport can later reuse the same
/// Codable operation model.
public actor SyncService {
    private static let hub = InMemorySyncHub()

    private var status: SyncStatus = .disconnected
    private var roomId: String?
    private var peer: SyncPeer
    private var revision: Int = 0
    private var statusListeners: [@Sendable (SyncStatus) -> Void] = []

    public init(peer: SyncPeer = SyncPeer()) {
        self.peer = peer
    }

    public func getStatus() -> SyncStatus { status }
    public func getRoomId() -> String? { roomId }
    public func getPeer() -> SyncPeer { peer }
    public func getRevision() -> Int { revision }

    public func addStatusListener(_ listener: @escaping @Sendable (SyncStatus) -> Void) {
        statusListeners.append(listener)
    }

    /// Generate a cryptographically strong-enough opaque room ID for local
    /// collaboration rendezvous. UUID v4 gives 122 random bits.
    public func generateRoomId() -> String {
        UUID().uuidString
    }

    /// Backward-compatible fire-and-forget connection entrypoint.
    public func connect(roomId: String) {
        Task { await connectToRoom(roomId: roomId, initialDocument: nil) }
    }

    /// Connect to a sync room and optionally seed it with the local document.
    @discardableResult
    public func connectToRoom(roomId: String, initialDocument: HypeDocument? = nil) async -> SyncCheckpoint {
        let normalizedRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoomId.isEmpty else {
            status = .error
            notifyListeners()
            return SyncCheckpoint(roomId: roomId, revision: revision, document: nil, operations: [])
        }

        self.roomId = normalizedRoomId
        self.status = .connecting
        notifyListeners()

        let checkpoint = await Self.hub.join(roomId: normalizedRoomId, peer: peer, initialDocument: initialDocument)
        self.revision = checkpoint.revision
        self.status = .connected
        notifyListeners()
        return checkpoint
    }

    /// Publish one operation and update this peer's local revision.
    @discardableResult
    public func publish(_ operation: SyncOperation) async -> SyncPublishResult {
        await publish(SyncChangeSet(baseRevision: operation.baseRevision, operations: [operation]))
    }

    /// Publish a batch of operations and update this peer's local revision.
    @discardableResult
    public func publish(_ changeSet: SyncChangeSet) async -> SyncPublishResult {
        guard status == .connected, let roomId else {
            return SyncPublishResult(accepted: false, revision: revision, document: nil, conflicts: [
                SyncConflict(operationId: changeSet.operations.first?.id ?? UUID(), entityKey: "session", localBaseRevision: revision, remoteRevision: revision, reason: "Not connected to a sync room.")
            ], appliedOperationIds: [])
        }
        let result = await Self.hub.publish(roomId: roomId, changeSet: changeSet)
        revision = result.revision
        return result
    }

    /// Pull the latest room checkpoint into this peer.
    public func pull() async -> SyncCheckpoint? {
        guard let roomId else { return nil }
        guard let checkpoint = await Self.hub.checkpoint(roomId: roomId, afterRevision: revision) else { return nil }
        revision = checkpoint.revision
        return checkpoint
    }

    /// Disconnect from sync.
    public func disconnect() async {
        if let roomId {
            await Self.hub.leave(roomId: roomId, peerId: peer.id)
        }
        status = .disconnected
        roomId = nil
        notifyListeners()
    }

    /// Backward-compatible synchronous disconnect for older callers.
    public func disconnectNow() {
        let oldRoomId = roomId
        let oldPeerId = peer.id
        status = .disconnected
        roomId = nil
        notifyListeners()
        if let oldRoomId {
            Task { await Self.hub.leave(roomId: oldRoomId, peerId: oldPeerId) }
        }
    }

    public func makeReplaceDocumentOperation(document: HypeDocument) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .replaceDocument, document: document)
    }

    public func makeUpdateStackOperation(_ stack: Stack) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .updateStack, stack: stack)
    }

    public func makeUpsertPartOperation(_ part: Part) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .upsertPart, part: part)
    }

    public func makeDeletePartOperation(partId: UUID) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .deletePart, partId: partId)
    }

    public func makeUpsertCardOperation(_ card: Card) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .upsertCard, card: card)
    }

    public func makeSetPaintLayerOperation(_ layer: CardPaintLayer) -> SyncOperation {
        SyncOperation(peerId: peer.id, baseRevision: revision, kind: .setPaintLayer, paintLayer: layer)
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
