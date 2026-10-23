import AppKit
import Foundation

/// The macOS boundary for opening a browser. Completion reports the system result,
/// so callers never count a link before the launch is confirmed.
@MainActor
protocol BrowserLauncher {
    func applicationURL(for bundleID: String) -> URL?
    func launch(
        _ plan: BrowserManager.BrowserLaunchPlan,
        completion: @MainActor @escaping (String?) -> Void
    )
}

@MainActor
final class SystemBrowserLauncher: BrowserLauncher {
    func applicationURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func launch(
        _ plan: BrowserManager.BrowserLaunchPlan,
        completion: @MainActor @escaping (String?) -> Void
    ) {
        #if !APP_STORE
        if plan.usesDirectOpenTool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = plan.directOpenArguments
            process.terminationHandler = { terminated in
                let failure = terminated.terminationStatus == 0
                    ? nil : "open exited with status \(terminated.terminationStatus)"
                Task { @MainActor in completion(failure) }
            }
            do {
                try process.run()
            } catch {
                completion(error.localizedDescription)
            }
            return
        }
        #endif

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = plan.createsNewApplicationInstance
        configuration.arguments = plan.deliveredApplicationArguments
        NSWorkspace.shared.open(
            plan.documentURLs, withApplicationAt: plan.appURL, configuration: configuration
        ) { application, error in
            let failure = error?.localizedDescription ?? (application == nil ? "macOS did not open the browser" : nil)
            Task { @MainActor in completion(failure) }
        }
    }
}
