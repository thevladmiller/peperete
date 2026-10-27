import Foundation
import Darwin

public struct Store: Sendable {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("boards.json") }
    public init(directory: URL? = nil) {
        if let directory { self.directory = directory }
        else if let override = ProcessInfo.processInfo.environment["PEPERETE_DATA_DIR"] {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            // The sandboxed widget has a narrow entitlement for this one directory.
            // Its Foundation home URL points into its container; POSIX returns the user's real home.
            #if PEPERETE_WIDGET
            let actualHome = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir), isDirectory: true) }
            self.directory = (actualHome ?? FileManager.default.homeDirectoryForCurrentUser)
                .appendingPathComponent("Library/Application Support/Peperete", isDirectory: true)
            #else
            self.directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Peperete", isDirectory: true)
            #endif
        }
    }
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private func readUnlocked() throws -> Database {
        guard FileManager.default.fileExists(atPath: file.path) else { return Database() }
        let db = try Self.decoder().decode(Database.self, from: Data(contentsOf: file)); try db.validate(); return db
    }
    public func read() throws -> Database { try locked { try readUnlocked() } }
    @discardableResult public func update<T>(_ mutation: (inout Database) throws -> T) throws -> T {
        let (result, saved): (T, Database) = try locked {
            var db = try readUnlocked()
            let before = db
            let result = try mutation(&db)
            db.recordChanges(from: before)
            try db.validate()
            if FileManager.default.fileExists(atPath: file.path) {
                let backups = directory.appendingPathComponent("Backups", isDirectory: true)
                try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                let backup = backups.appendingPathComponent("revision-\(db.revision)-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            db.revision += 1
            try Self.encoder().encode(db).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return (result, db)
        }
        #if !PEPERETE_WIDGET
        _ = DocumentationPublisher.publish(saved)
        #endif
        return result
    }
    public func export(to url: URL) throws { try Self.encoder().encode(read()).write(to: url, options: .atomic) }
    @discardableResult public func importFile(_ url: URL) throws -> Int {
        let incoming = try Self.decoder().decode(Database.self, from: Data(contentsOf: url))
        return try update { try $0.merge(incoming) }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw StoreError.invalid("Could not open the data lock.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.invalid("Could not lock the data file.") }
        defer { flock(descriptor, LOCK_UN) }
        return try action()
    }
}
