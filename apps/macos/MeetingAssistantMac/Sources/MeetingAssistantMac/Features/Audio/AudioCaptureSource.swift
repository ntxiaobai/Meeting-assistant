import Foundation

protocol AudioCaptureSource: AnyObject {
    var onPcm: (([Int16]) -> Void)? { get set }
    func start() async throws
    func stop() async
}
