import Foundation
import Network

@MainActor
public protocol NetworkMonitorDelegate: AnyObject {
    func networkMonitorDidChangePath(_ monitor: NetworkMonitor, isConnected: Bool, isCellular: Bool)
}

public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()
    public weak var delegate: NetworkMonitorDelegate?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.remotecontroller.networkmonitor")

    public private(set) var isConnected: Bool = true
    public private(set) var isCellular: Bool = false

    public init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let connected = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular)

            DispatchQueue.main.async {
                self.isConnected = connected
                self.isCellular = cellular
                self.delegate?.networkMonitorDidChangePath(self, isConnected: connected, isCellular: cellular)
            }
        }
    }

    public func start() {
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}
