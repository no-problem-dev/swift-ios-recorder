import Testing
import SwiftUI
@testable import iOSRecorderUI
import iOSRecorder

@MainActor
@Suite struct DebugSectionFactoryTests {
    @Test func maintenanceSectionCarriesStores() {
        let log = DebugLog()
        let section = DebugSection.maintenance(log: log)
        #expect(section.id == "maintenance")
        guard case .maintenance(let carried, _, _) = section.content else {
            Issue.record("content が maintenance ではない")
            return
        }
        #expect(carried === log)
    }

    @Test func screenSectionIsNavigationLink() {
        let section = DebugSection.screen(id: "x", title: "X", icon: "star") { Text("dest") }
        #expect(section.layout == .navigationLink)
        guard case .screen = section.content else {
            Issue.record("content が screen ではない")
            return
        }
    }

    @Test func designSystemCatalogPresetHasStableID() {
        let section = DebugSection.designSystemCatalog()
        #expect(section.id == "design-catalog")
        #expect(section.layout == .navigationLink)
    }
}
