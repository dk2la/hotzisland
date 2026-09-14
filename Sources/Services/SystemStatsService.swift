import Darwin
import Foundation
import Observation
import OSLog

/// Samples CPU load, memory pressure and network throughput. All readings
/// come from Mach/BSD calls — cheap, but pointless while nobody is looking,
/// so the poll loop only runs while at least one observer is registered.
@MainActor
@Observable
final class SystemStatsService {
    /// 0...1 across all cores.
    private(set) var cpuUsage: Double = 0
    /// Bytes.
    private(set) var memoryUsed: UInt64 = 0
    private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    /// Bytes per second.
    private(set) var downloadRate: Double = 0
    private(set) var uploadRate: Double = 0
    /// Last 16 CPU samples for the Sys history strip.
    private(set) var cpuHistory: [Double] = []

    /// Number of live `beginObserving()` calls without a matching end.
    /// Sampling runs only while this is above zero.
    @ObservationIgnored private(set) var observerCount = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var previousTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var previousTraffic: (rx: UInt64, tx: UInt64, at: Date)?
    @ObservationIgnored private var didLogFirstSample = false
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "stats")

    /// `mach_host_self()` hands out a fresh send right on every call and
    /// they are never returned, so the port is fetched once and kept.
    @ObservationIgnored private let hostPort: mach_port_t
    @ObservationIgnored private let pageSize: UInt64

    init() {
        hostPort = mach_host_self()
        var hostPageSize: vm_size_t = 0
        host_page_size(hostPort, &hostPageSize)
        pageSize = UInt64(hostPageSize)
    }

    // MARK: - Observers

    /// Registers a reader. The first one starts the poll loop with an
    /// immediate sample so the UI is not blank until the next tick.
    func beginObserving() {
        observerCount += 1
        guard observerCount == 1, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            // The very first pass has no baseline for the CPU/network deltas,
            // so the second sample follows quickly; after that, every 2 s.
            var interval: Duration = .milliseconds(500)
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: interval)
                interval = .seconds(2)
            }
        }
    }

    /// Unregisters a reader. When the last one leaves the loop stops; the
    /// previous tick baselines are kept so the next open shows a value at once.
    func endObserving() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    /// One synchronous refresh, for callers that need a reading without
    /// keeping the loop alive (e.g. a one-shot tool).
    func sampleNow() {
        sample()
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()

        if !didLogFirstSample {
            didLogFirstSample = true
            log.info("""
            first sample: cpu=\(Int(self.cpuUsage * 100), privacy: .public)% \
            mem=\(self.memoryUsed / 1_073_741_824, privacy: .public)/\(self.memoryTotal / 1_073_741_824, privacy: .public)GB \
            net rx=\(Int(self.downloadRate), privacy: .public)B/s
            """)
        }
    }

    // MARK: - CPU

    private func sampleCPU() {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(
            hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
        ) == KERN_SUCCESS, let info else { return }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }

        if let previous = previousTicks, total > previous.total {
            let busyDelta = Double(busy - previous.busy)
            let totalDelta = Double(total - previous.total)
            cpuUsage = totalDelta > 0 ? min(1, busyDelta / totalDelta) : 0
            cpuHistory.append(cpuUsage)
            if cpuHistory.count > 16 {
                cpuHistory.removeFirst(cpuHistory.count - 16)
            }
        }
        previousTicks = (busy, total)
    }

    // MARK: - Memory

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // "Used" the way Activity Monitor counts it: app + wired + compressed.
        let used = (UInt64(stats.internal_page_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)) * pageSize
        memoryUsed = used
    }

    // MARK: - Network

    private func sampleNetwork() {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var pointer = addrs
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let sockaddr = current.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = current.pointee.ifa_data
            else { continue }
            let name = String(cString: current.pointee.ifa_name)
            // Physical interfaces only — skip loopback, tunnels, bridges.
            guard name.hasPrefix("en") else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(data.ifi_ibytes)
            tx += UInt64(data.ifi_obytes)
        }

        let now = Date()
        if let previous = previousTraffic {
            let elapsed = now.timeIntervalSince(previous.at)
            // The kernel counters are 32-bit and wrap — skip that sample.
            if elapsed > 0, rx >= previous.rx, tx >= previous.tx {
                downloadRate = Double(rx - previous.rx) / elapsed
                uploadRate = Double(tx - previous.tx) / elapsed
            }
        }
        previousTraffic = (rx, tx, now)
    }
}
