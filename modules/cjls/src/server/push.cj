package cjls.server

import std.collection.HashMap
import std.sync.Mutex
import stdx.log.Logger
import calca.Cancelled
import loupe.vfs.VfsPath
import cjls.lsp_types.*

/**
 * Diagnostics pushed to a client that cannot pull them (D14). The server schedules a publish after
 * every write (S7); each runs on a `spawn` of its own, and a document's publish is sent only if no
 * newer one has been scheduled for it since (S9), so a slow publish never overwrites a newer one.
 *
 * The generation is kept per document, not for the whole server: a document closed is cleared at
 * once, and that must not drop what an earlier publish still has to send for the others.
 */
class DiagnosticsPush {
    private let lock = Mutex()
    // guarded by `lock`: the generation of the latest publish scheduled for each open document
    private let latest = HashMap<VfsPath, Int64>()
    private var generations = 0

    DiagnosticsPush(
        private let diagnosticsOf: (ServerSnapshot, VfsPath) -> Array<Diagnostic>,
        private let client: Client,
        private let logger: Logger
    ) {}

    /**
     * Publishes the diagnostics of `documents`, paths and versions, as `snapshot` has them. The
     * snapshot is taken on the read loop, so it holds what every message before did; a write after it
     * cancels the publish, and has scheduled one of its own.
     */
    func schedule(snapshot: ServerSnapshot, documents: Array<(VfsPath, Int32)>): Future<Unit> {
        let generation = synchronized(lock) {
            generations++
            for ((path, _) in documents) {
                latest[path] = generations
            }
            generations
        }
        spawn {
            try {
                for ((path, version) in documents) {
                    publish(path, version, diagnosticsOf(snapshot, path), generation)
                }
            } catch (_: Cancelled) {
                logger.debug("push cancelled", [("reason", "the content was modified")])
            } catch (e: Exception) {
                failed(e)
            }
        }
    }

    /**
     * Publishes an empty list for a document just closed, at once: what it had would stay in the
     * client's list otherwise. A publish still running for it is dropped.
     */
    func clear(path: VfsPath): Unit {
        try {
            synchronized(lock) {
                latest.remove(path)
                client.notify(PublishDiagnosticsNotificationSpec(), PublishDiagnosticsParams(uri: path.toUri(), diagnostics: []))
            }
        } catch (e: Exception) {
            failed(e)
        }
    }

    /**
     * A publish that could not be sent: expected once the connection is closed, as a `spawn` may outlive it.
     */
    private func failed(e: Exception): Unit {
        if (client.isClosed()) {
            logger.debug("push dropped", [("reason", "the connection is closed")])
        } else {
            logger.error("push failed", [("cause", e)])
        }
    }

    private func publish(path: VfsPath, version: Int32, diagnostics: Array<Diagnostic>, generation: Int64): Unit {
        synchronized(lock) {
            if (latest.get(path) != generation) {
                logger.debug("push dropped", [("reason", "a newer one was scheduled"), ("uri", path.toUri())])
                return
            }
            client.notify(PublishDiagnosticsNotificationSpec(),
                PublishDiagnosticsParams(uri: path.toUri(), version: version, diagnostics: diagnostics))
        }
    }
}
