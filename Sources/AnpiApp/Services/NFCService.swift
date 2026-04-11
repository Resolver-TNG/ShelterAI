import Foundation

// MARK: - Phase 2 スタブ

protocol NFCServiceProtocol {
    func startScan(completion: @escaping (Result<String, Error>) -> Void)
}

final class NFCServiceStub: NFCServiceProtocol {
    func startScan(completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(NFCError.notImplemented))
    }

    enum NFCError: LocalizedError {
        case notImplemented
        var errorDescription: String? { "NFC機能はPhase 2で実装予定です" }
    }
}
