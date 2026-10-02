import Foundation
import SQLite3
import CalendarSyncCore

private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

public enum SyncStoreError: Error, LocalizedError, Sendable {
    case database(Int32)
    case unreadableState

    public var errorDescription: String? {
        switch self {
        case .database(let code): "캘린더 동기화 저장소 오류(\(code))"
        case .unreadableState: "캘린더 동기화 상태를 읽을 수 없습니다. 원본 파일을 보존했습니다"
        }
    }
}

public struct CalendarSyncConfiguration: Codable, Sendable {
    public var daouBaseURL = "https://lululab.daouoffice.com"
    public var daouEmail = ""
    public var daouCalendarURL: String?
    public var googleClientID = ""
    public var googleCalendarID: String?
    public var enabled = false
    public var previewAccepted = false
    public var systemAccountsConfirmed: Bool?

    public init() {}

    public var hasSelectedPair: Bool {
        daouCalendarURL != nil && googleCalendarID != nil
    }
}

public struct PendingSyncOperation: Codable, Sendable {
    public var id: String
    public var operation: SyncOperation
    public var newBaseline: SyncBaseline
    public var preparedAt: Date

    public init(id: String, operation: SyncOperation, newBaseline: SyncBaseline, preparedAt: Date = Date()) {
        self.id = id
        self.operation = operation
        self.newBaseline = newBaseline
        self.preparedAt = preparedAt
    }
}

public struct CalendarSyncState: Codable, Sendable {
    public var version = 1
    public var configuration = CalendarSyncConfiguration()
    public var mappings: [String: CalendarMapping] = [:]
    public var daouObserved: [String: CalendarEvent] = [:]
    public var googleObserved: [String: CalendarEvent] = [:]
    public var googleCursor: String?
    public var pendingOperations: [String: PendingSyncOperation] = [:]
    public var conflicts: [String: SyncConflict] = [:]
    public var lastSuccessAt: Date?
    public var nextRunAt: Date?
    public var lastErrorCode: String?
    public var consecutiveFailures = 0
    public var pairKey: String?
    public var lastPreview: SyncRunSummary?
    // Optional so sync.sqlite records from earlier versions remain readable.
    public var initialPreviewFingerprint: String?
    public var initialWriteAuthorized: Bool?

    public init() {}
}

public struct SyncRunSummary: Codable, Sendable {
    public var toDaou = 0
    public var toGoogle = 0
    public var conflicts = 0
    public var held = 0
    public var excluded = 0
    public var completed = 0

    public init() {}
}

/// A single transactional state document in SQLite. The Keychain owns credentials.
public actor SyncStore {
    public static let standardURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/HappyLulu/CalendarSync/sync.sqlite")

    private let connection: SQLiteConnection
    private var database: OpaquePointer { connection.pointer }

    public init(url: URL = SyncStore.standardURL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        var pointer: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &pointer,
                                    SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw SyncStoreError.database(status)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            guard sqlite3_exec(pointer, "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK (id = 1), document BLOB NOT NULL);", nil, nil, nil) == SQLITE_OK else {
                throw SyncStoreError.database(sqlite3_errcode(pointer))
            }
        } catch {
            sqlite3_close(pointer)
            throw error
        }
        connection = SQLiteConnection(pointer)
    }

    public func load() throws -> CalendarSyncState {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT document FROM state WHERE id = 1", -1, &statement, nil) == SQLITE_OK else {
            throw SyncStoreError.database(sqlite3_errcode(database))
        }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return CalendarSyncState() }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw SyncStoreError.database(sqlite3_errcode(database))
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let state = try? JSONDecoder().decode(CalendarSyncState.self, from: data), state.version == 1 else {
            throw SyncStoreError.unreadableState
        }
        return state
    }

    public func save(_ state: CalendarSyncState) throws {
        let data = try JSONEncoder().encode(state)
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw SyncStoreError.database(sqlite3_errcode(database))
        }
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database,
                "INSERT INTO state (id, document) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET document = excluded.document",
                -1, &statement, nil) == SQLITE_OK else {
                throw SyncStoreError.database(sqlite3_errcode(database))
            }
            defer { sqlite3_finalize(statement) }
            let status = data.withUnsafeBytes { bytes -> Int32 in
                let bound = sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), nil)
                guard bound == SQLITE_OK else { return bound }
                return sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else {
                throw SyncStoreError.database(sqlite3_errcode(database))
            }
            guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw SyncStoreError.database(sqlite3_errcode(database))
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
}
