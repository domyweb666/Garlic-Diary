import CoreMotion
import Foundation

/// 手機傾斜，籃子裡的蒜就往那邊滾。CoreMotion 不用問權限。
final class TiltSensor {
    private let mm = CMMotionManager()
    private(set) var running = false
    var onGravity: ((Double, Double) -> Void)?

    func start() {
        guard !running, mm.isDeviceMotionAvailable else { return }
        running = true
        mm.deviceMotionUpdateInterval = 1.0 / 30.0
        mm.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // 直拿手機、頂端朝上時 gravity 約是 (0, -1, 0)；螢幕的 y 往下是正，所以反過來
            self.onGravity?(g.x, -g.y)
        }
    }

    func stop() {
        guard running else { return }
        mm.stopDeviceMotionUpdates()
        running = false
    }
}
