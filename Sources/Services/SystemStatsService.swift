import Darwin
import Foundation
import Observation
import OSLog

/// Samples CPU load, memory pressure and network throughput. All readings
/// come from Mach/BSD calls — cheap enough to poll continuously.
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

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var previousTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var previousTraffic: (rx: UInt64, tx: UInt64, at: Date)?
    @ObservationIgnored private var didLogFirstSample = false
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "stats")

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
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
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
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
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = UInt64(hostPageSize)
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
