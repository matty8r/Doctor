import Foundation

/// Watches a single file for changes made outside the app.
///
/// Most editors save atomically (write to a temp file, then rename over the
/// original), which destroys the file descriptor we're watching. So on a
/// rename or delete we re-arm against the path rather than giving up.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.doctor.filewatcher")

    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        guard arm() else { return nil }
    }

    deinit {
        disarm()
    }

    @discardableResult
    private func arm() -> Bool {
        disarm()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.rename) || flags.contains(.delete) {
                // Atomic save: the path may already point at the new inode.
                self.queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.arm()
                    self?.notify()
                }
            } else {
                self.notify()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        self.source = source
        return true
    }

    private func disarm() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Coalesce bursts — a single save can produce several events.
    private func notify() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
