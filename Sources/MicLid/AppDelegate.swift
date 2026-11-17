import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: Controller?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = Controller()
        self.controller = controller
        statusItemController = StatusItemController(controller: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
