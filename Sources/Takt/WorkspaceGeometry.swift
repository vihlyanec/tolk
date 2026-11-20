import SwiftUI

enum WorkspaceGeometry {
    static let minimumWindow = CGSize(width: 640, height: 440)
    static let minimumSettings = CGSize(width: 440, height: 320)

    static func fittedFrame(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: max(visible.minX, min(frame.minX, visible.maxX - width)),
                      y: max(visible.minY, min(frame.maxY - height, visible.maxY - height)),
                      width: width, height: height)
    }

    static func presentationHeight(_ preferred: CGFloat, in height: CGFloat?) -> CGFloat {
        guard let height else { return preferred }
        return max(0, min(preferred, height - 44))
    }
}

private struct WorkspaceHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var workspaceHeight: CGFloat? {
        get { self[WorkspaceHeightKey.self] }
        set { self[WorkspaceHeightKey.self] = newValue }
    }
}
