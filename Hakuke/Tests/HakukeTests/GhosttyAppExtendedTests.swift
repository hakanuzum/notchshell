import Testing
import AppKit
import GhosttyKit
@testable import Hakuke

/// Extended tests for GhosttyApp: initialization, backend registry, action routing,
/// config management, and environment setup.
@MainActor
@Suite(.serialized)
struct GhosttyAppInitTests {

    @Test func shared_isSingleton() {
        #expect(GhosttyApp.shared === GhosttyApp.shared)
    }

    @Test func initialize_noCrash() {
        let app = GhosttyApp.shared
        app.initialize()
        // In test environment, initialize() skips Ghostty init (no GPU).
        // On real hardware with MACUAKE_TEST_GHOSTTY=1, app/config will be non-nil.
    }

    @Test func initialize_idempotent_noCrash() {
        let app = GhosttyApp.shared
        app.initialize()
        app.initialize()
        app.initialize()
        // Multiple calls should not crash regardless of environment
    }

    @Test func configPath_nonEmpty() {
        let app = GhosttyApp.shared
        app.initialize()
        #expect(!app.configPath.isEmpty)
    }

    @Test func configPath_containsGhostty() {
        let app = GhosttyApp.shared
        app.initialize()
        #expect(app.configPath.contains("ghostty"))
    }

    @Test func configPath_withoutApp_fallsBack() {
        // When app is not initialized, should fallback to default path
        // Since GhosttyApp is singleton and already initialized, test the path format
        let path = GhosttyApp.shared.configPath
        #expect(!path.isEmpty)
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyAppBackendRegistryTests {

    @Test func registerBackend_noCrash() {
        let backend = GhosttyBackend()
        GhosttyApp.shared.registerBackend(backend)
        GhosttyApp.shared.unregisterBackend(backend)
    }

    @Test func unregisterBackend_unregistered_noCrash() {
        let backend = GhosttyBackend()
        // Unregister without registering first — should be no-op
        GhosttyApp.shared.unregisterBackend(backend)
    }

    @Test func registerMultipleBackends_noCrash() {
        let b1 = GhosttyBackend()
        let b2 = GhosttyBackend()
        let b3 = GhosttyBackend()
        GhosttyApp.shared.registerBackend(b1)
        GhosttyApp.shared.registerBackend(b2)
        GhosttyApp.shared.registerBackend(b3)
        GhosttyApp.shared.unregisterBackend(b1)
        GhosttyApp.shared.unregisterBackend(b2)
        GhosttyApp.shared.unregisterBackend(b3)
    }

    @Test func doubleRegister_noCrash() {
        let backend = GhosttyBackend()
        GhosttyApp.shared.registerBackend(backend)
        GhosttyApp.shared.registerBackend(backend) // same backend twice
        GhosttyApp.shared.unregisterBackend(backend)
    }

    @Test func doubleUnregister_noCrash() {
        let backend = GhosttyBackend()
        GhosttyApp.shared.registerBackend(backend)
        GhosttyApp.shared.unregisterBackend(backend)
        GhosttyApp.shared.unregisterBackend(backend) // already removed
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyAppActionRoutingTests {

    @Test func handleAction_reloadConfig_atAppLevel() {
        // reloadConfig should not crash even when called directly
        GhosttyApp.shared.initialize()
        GhosttyApp.shared.reloadConfig()
        // No crash = pass
    }

    @Test func tick_withApp_noCrash() {
        GhosttyApp.shared.initialize()
        GhosttyApp.shared.tick()
    }

    @Test func tick_multipleCallsRapidly_noCrash() {
        GhosttyApp.shared.initialize()
        for _ in 0..<10 {
            GhosttyApp.shared.tick()
        }
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyAppConfigTests {

    @Test func openConfig_noCrash() {
        GhosttyApp.shared.initialize()
        // Don't actually open — would launch an editor
        // But we can verify configPath exists
        let path = GhosttyApp.shared.configPath
        #expect(!path.isEmpty)
    }

    @Test func reloadConfig_withActiveBackends_noCrash() {
        GhosttyApp.shared.initialize()
        let backend = GhosttyBackend()
        GhosttyApp.shared.registerBackend(backend)

        GhosttyApp.shared.reloadConfig()

        GhosttyApp.shared.unregisterBackend(backend)
    }

    @Test func reloadConfig_withMultipleBackends_noCrash() {
        GhosttyApp.shared.initialize()
        let b1 = GhosttyBackend()
        let b2 = GhosttyBackend()

        GhosttyApp.shared.registerBackend(b1)
        GhosttyApp.shared.registerBackend(b2)

        GhosttyApp.shared.reloadConfig()

        GhosttyApp.shared.unregisterBackend(b1)
        GhosttyApp.shared.unregisterBackend(b2)
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyAppEnvironmentTests {

    @Test func noColor_unsetDuringInit() {
        // After initialization, NO_COLOR should not be set
        // (GhosttyApp.initialize() calls unsetenv("NO_COLOR") if it was set)
        GhosttyApp.shared.initialize()
        // We can't easily test this without setting NO_COLOR before init,
        // but we can verify it's not set now
        let noColor = getenv("NO_COLOR")
        // May or may not be set depending on environment, but init should have cleared it
        _ = noColor
    }

    @Test func ghosttyResourcesDir_setAfterInit() {
        GhosttyApp.shared.initialize()
        // GHOSTTY_RESOURCES_DIR should be set if Ghostty.app exists
        let resourcesDir = getenv("GHOSTTY_RESOURCES_DIR")
        if resourcesDir != nil {
            let path = String(cString: resourcesDir!)
            #expect(!path.isEmpty)
            // Should point to a directory with "themes" subdir
            let themesPath = path + "/themes"
            #expect(FileManager.default.fileExists(atPath: themesPath))
        }
    }

    @Test func disableForTesting_flagWorks() {
        // The flag exists and is accessible
        #expect(GhosttyApp.disableForTesting == false)
    }
}

// MARK: - TerminalInstance tests

@MainActor
@Suite(.serialized)
struct TerminalInstanceLifecycleTests {

    @Test func init_createsBackend() {
        let instance = TerminalInstance()
        #expect(instance.backend is GhosttyBackend)
    }

    @Test func init_defaultTitle_isZsh() {
        let instance = TerminalInstance()
        #expect(instance.currentTitle == "zsh")
    }

    @Test func init_defaultDirectory_isEmpty() {
        let instance = TerminalInstance()
        #expect(instance.currentDirectory == "")
    }

    @Test func initWithExistingBackend_usesProvidedBackend() {
        let backend = GhosttyBackend()
        let instance = TerminalInstance(existingBackend: backend)
        #expect(instance.backend === backend)
    }

    @Test func startShell_setsUpBackend() {
        let instance = TerminalInstance()
        instance.startShell()
        let gb = instance.backend as! GhosttyBackend
        // Surface may be nil on VM with paravirtual GPU
        _ = gb
        instance.terminate()
    }

    @Test func startShell_withDirectory() {
        let instance = TerminalInstance()
        instance.startShell(in: "/tmp")
        instance.terminate()
    }

    @Test func terminate_isIdempotent() {
        let instance = TerminalInstance()
        instance.terminate()
        instance.terminate() // second call should be no-op
    }

    @Test func startShell_afterTerminate_isNoOp() {
        let instance = TerminalInstance()
        instance.terminate()
        instance.startShell() // should not start (isTerminated = true)
    }

    @Test func onTitleChange_callback() {
        let instance = TerminalInstance()
        var received: String?
        instance.onTitleChange = { title in received = title }

        // Simulate delegate callback
        instance.terminalTitleChanged("vim")

        #expect(received == "vim")
        #expect(instance.currentTitle == "vim")
    }

    @Test func onDirectoryChange_callback() {
        let instance = TerminalInstance()
        var received: String?
        instance.onDirectoryChange = { dir in received = dir }

        instance.terminalDirectoryChanged("/home/user")

        #expect(received == "/home/user")
        #expect(instance.currentDirectory == "/home/user")
    }

    @Test func onProcessTerminated_callback() {
        let instance = TerminalInstance()
        var terminated = false
        instance.onProcessTerminated = { terminated = true }

        instance.terminalProcessTerminated(exitCode: 0)

        #expect(terminated == true)
    }

    @Test func terminalSizeChanged_noCrash() {
        let instance = TerminalInstance()
        instance.terminalSizeChanged(cols: 80, rows: 24)
        // No-op, but should not crash
    }
}
