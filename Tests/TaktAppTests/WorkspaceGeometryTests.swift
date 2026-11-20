import CoreGraphics
import Testing
@testable import Takt

@MainActor
struct WorkspaceGeometryTests {
    @Test func fitsOversizedWindowOnSecondaryDisplay() {
        let visible = CGRect(x: -1024, y: 40, width: 1024, height: 720)
        let restored = CGRect(x: -1200, y: -80, width: 1440, height: 880)
        #expect(WorkspaceGeometry.fittedFrame(restored, in: visible) == visible)
    }

    @Test func clampsPositionWithoutResizingAWindowThatFits() {
        let visible = CGRect(x: -1024, y: 40, width: 1024, height: 720)
        let partiallyOffscreen = CGRect(x: -400, y: 240, width: 640, height: 440)
        let fitted = CGRect(x: -640, y: 240, width: 640, height: 440)
        #expect(WorkspaceGeometry.fittedFrame(partiallyOffscreen, in: visible) == fitted)
        #expect(WorkspaceGeometry.fittedFrame(fitted, in: visible) == fitted)
    }

    @Test func presentationUsesTheHostingWindowHeight() {
        #expect(WorkspaceGeometry.presentationHeight(680, in: 440) == 396)
        #expect(WorkspaceGeometry.presentationHeight(680, in: 920) == 680)
        #expect(WorkspaceGeometry.presentationHeight(620, in: nil) == 620)
    }
}
