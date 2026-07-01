import XCTest
@testable import OpenUsage

/// Covers the per-provider menu-bar visibility toggle on `LayoutStore` (Settings ▸ Menu Bar): hiding
/// auto-removes a provider's pins and remembers them, re-enabling restores the same pins (filtered
/// against the current registry), the strip groups drop hidden providers, and the state survives
/// `resetToDefault` / `resetProvider` plus persistence across relaunch. Mirrors `MenuBarPinTests`'s
/// fixture so the hide+pin interplay is testable end-to-end.
@MainActor
final class MenuBarHiddenProvidersTests: XCTestCase {
    func testNothingHiddenByDefault() {
        let store = makeStore("default")
        XCTAssertTrue(store.hiddenProviderIDs.isEmpty)
        XCTAssertTrue(store.hiddenProviderPins.isEmpty)
    }

    func testHideProviderRemovesPinsAndRemembersThem() {
        let store = makeStore("hide")
        store.setPinned(true, for: "a.m1")
        store.setPinned(true, for: "b.m1")

        XCTAssertEqual(store.pinnedGroups.map(\.provider.id), ["a", "b"])

        store.setProviderHiddenFromMenuBar("a", hidden: true)

        XCTAssertTrue(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertFalse(store.isPinned("a.m1")) // pulled out of the active set
        XCTAssertEqual(store.hiddenProviderPins["a"], ["a.m1"]) // remembered
        XCTAssertEqual(store.pinnedGroups.map(\.provider.id), ["b"]) // strip drops hidden provider
    }

    func testReEnablingProviderRestoresRememberedPins() {
        let store = makeStore("restore")
        store.setPinned(true, for: "a.m1")
        store.setPinned(true, for: "a.m2")

        store.setProviderHiddenFromMenuBar("a", hidden: true)
        XCTAssertEqual(store.pinnedGroups.map(\.provider.id), [])

        store.setProviderHiddenFromMenuBar("a", hidden: false)

        XCTAssertFalse(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertTrue(store.isPinned("a.m1"))
        XCTAssertTrue(store.isPinned("a.m2"))
        XCTAssertNil(store.hiddenProviderPins["a"]) // snapshot cleared after restore
        XCTAssertEqual(store.pinnedGroups.map(\.provider.id), ["a"])
    }

    func testHideWithoutPinsIsHarmless() {
        let store = makeStore("noPins")
        store.setPinned(true, for: "a.m1")
        // "b" has no pins — hiding it should still record the flag but leave nothing to remember.
        store.setProviderHiddenFromMenuBar("b", hidden: true)

        XCTAssertTrue(store.isProviderHiddenFromMenuBar("b"))
        XCTAssertNil(store.hiddenProviderPins["b"])
        // Re-enabling an empty-hidden provider is a no-op for pins.
        store.setProviderHiddenFromMenuBar("b", hidden: false)
        XCTAssertFalse(store.isProviderHiddenFromMenuBar("b"))
    }

    func testStaleMetricDroppedOnReEnable() {
        // "a.m1" gets pinned, the user hides provider "a", then the registry loses m1. Re-enabling
        // must not resurrect m1 as a ghost pin (intersected against the live registry).
        let registry = makeRegistry()
        let defaults = makeDefaults("stale")
        let store = LayoutStore(registry: registry, defaults: defaults, storageKey: "layout")
        store.setPinned(true, for: "a.m1")
        store.setProviderHiddenFromMenuBar("a", hidden: true)

        let shrunken = WidgetRegistry(
            providers: registry.providers,
            descriptors: registry.descriptors.filter { $0.id != "a.m1" }
        )
        let reloaded = LayoutStore(registry: shrunken, defaults: defaults, storageKey: "layout")
        XCTAssertTrue(reloaded.isProviderHiddenFromMenuBar("a"))

        reloaded.setProviderHiddenFromMenuBar("a", hidden: false)

        XCTAssertFalse(reloaded.isPinned("a.m1")) // stale id dropped
        XCTAssertNil(reloaded.hiddenProviderPins["a"])
    }

    func testUnknownProviderIsNoOp() {
        let store = makeStore("unknown")
        store.setProviderHiddenFromMenuBar("ghost", hidden: true)
        XCTAssertFalse(store.isProviderHiddenFromMenuBar("ghost"))
        XCTAssertTrue(store.hiddenProviderIDs.isEmpty)
    }

    func testHidingAnAlreadyHiddenProviderIsNoOp() {
        let store = makeStore("alreadyHidden")
        store.setPinned(true, for: "a.m1")
        store.setProviderHiddenFromMenuBar("a", hidden: true)
        let pins = store.pinnedMetricIDs
        let hidden = store.hiddenProviderIDs

        store.setProviderHiddenFromMenuBar("a", hidden: true) // repeat — no-op

        XCTAssertEqual(store.pinnedMetricIDs, pins)
        XCTAssertEqual(store.hiddenProviderIDs, hidden)
    }

    func testDisabledProviderCanStillBeHidden() {
        // Hiding is independent of the provider's enabled state — even a disabled provider can be
        // hidden so the user's choice persists across enable/disable cycles.
        let store = LayoutStore(
            registry: makeRegistry(),
            defaults: makeDefaults("disabled"),
            storageKey: "layout",
            isProviderEnabled: { $0 != "a" }
        )
        store.setProviderHiddenFromMenuBar("a", hidden: true)
        XCTAssertTrue(store.isProviderHiddenFromMenuBar("a"))
        // The strip already drops disabled providers, so pinnedGroups stays empty either way.
        XCTAssertTrue(store.pinnedGroups.isEmpty)
    }

    func testPinnedGroupsHideMultipleProviders() {
        let store = makeStore("multi")
        for provider in ["a", "b", "c", "d"] {
            store.setPinned(true, for: "\(provider).m1")
        }
        store.setProviderHiddenFromMenuBar("a", hidden: true)
        store.setProviderHiddenFromMenuBar("c", hidden: true)

        XCTAssertEqual(store.pinnedGroups.map(\.provider.id), ["b", "d"])
        // pindesc-in-order should mirror pinnedGroups (which now filters hidden).
        XCTAssertEqual(store.pinnedDescriptorIDsInOrder, ["b.m1", "d.m1"])
    }

    func testHiddenStatePersistsAcrossReload() {
        let defaults = makeDefaults("persist")
        let store = LayoutStore(registry: makeRegistry(), defaults: defaults, storageKey: "layout")
        store.setPinned(true, for: "a.m1")
        store.setPinned(true, for: "a.m2")
        store.setProviderHiddenFromMenuBar("a", hidden: true)

        let reloaded = LayoutStore(registry: makeRegistry(), defaults: defaults, storageKey: "layout")
        XCTAssertTrue(reloaded.isProviderHiddenFromMenuBar("a"))
        XCTAssertEqual(reloaded.hiddenProviderPins["a"], ["a.m1", "a.m2"])
        XCTAssertFalse(reloaded.isPinned("a.m1"))

        reloaded.setProviderHiddenFromMenuBar("a", hidden: false)
        let reloadedAgain = LayoutStore(registry: makeRegistry(), defaults: defaults, storageKey: "layout")
        XCTAssertFalse(reloadedAgain.isProviderHiddenFromMenuBar("a"))
        XCTAssertTrue(reloadedAgain.isPinned("a.m1"))
        XCTAssertTrue(reloadedAgain.isPinned("a.m2"))
    }

    func testInvalidHiddenProviderIDsDroppedOnLoad() {
        let defaults = makeDefaults("invalid")
        defaults.set(["a", "ghost.provider"], forKey: "layout.menuBarHiddenProviders")
        let store = LayoutStore(registry: makeRegistry(), defaults: defaults, storageKey: "layout")

        XCTAssertTrue(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertFalse(store.isProviderHiddenFromMenuBar("ghost.provider"))
    }

    func testInvalidHiddenPinsDroppedOnLoad() {
        // Stale descriptor ids inside a hidden-provider pin snapshot must be filtered, otherwise
        // re-enabling would resurrect ghost pins.
        let defaults = makeDefaults("invalidPins")
        defaults.set(
            try? JSONEncoder().encode(["a": ["a.m1", "ghost.metric"], "b": []]),
            forKey: "layout.menuBarHiddenProviderPins"
        )
        let store = LayoutStore(registry: makeRegistry(), defaults: defaults, storageKey: "layout")

        XCTAssertEqual(store.hiddenProviderPins["a"], ["a.m1"]) // ghost.metric dropped
        XCTAssertNil(store.hiddenProviderPins["b"]) // empty value omitted
    }

    func testResetToDefaultClearsHiddenState() {
        let store = makeStore("resetAll")
        store.setPinned(true, for: "a.m1")
        store.setProviderHiddenFromMenuBar("a", hidden: true)
        XCTAssertFalse(store.hiddenProviderIDs.isEmpty)

        store.resetToDefault()

        XCTAssertTrue(store.hiddenProviderIDs.isEmpty)
        XCTAssertTrue(store.hiddenProviderPins.isEmpty)
    }

    func testResetProviderClearsItsOwnHiddenState() {
        let store = makeStore("resetOne")
        store.setPinned(true, for: "a.m1")
        store.setPinned(true, for: "b.m1")
        store.setProviderHiddenFromMenuBar("a", hidden: true)
        store.setProviderHiddenFromMenuBar("b", hidden: true)

        store.resetProvider("a")

        XCTAssertFalse(store.isProviderHiddenFromMenuBar("a")) // only this provider cleared
        XCTAssertTrue(store.isProviderHiddenFromMenuBar("b"))  // other provider untouched
        XCTAssertNil(store.hiddenProviderPins["a"])
    }

    func testHideIsUndoable() {
        let store = makeStore("undo")
        store.setPinned(true, for: "a.m1")
        store.setPinned(true, for: "b.m1")
        let pinsBefore = store.pinnedMetricIDs

        store.setProviderHiddenFromMenuBar("a", hidden: true)
        XCTAssertTrue(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertFalse(store.isPinned("a.m1"))

        XCTAssertTrue(store.undo())
        XCTAssertFalse(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertEqual(store.pinnedMetricIDs, pinsBefore)
    }

    func testReEnableIsUndoable() {
        let store = makeStore("undoShow")
        store.setPinned(true, for: "a.m1")
        store.setProviderHiddenFromMenuBar("a", hidden: true)

        let hiddenBefore = store.hiddenProviderIDs
        let pinsBefore = store.pinnedMetricIDs

        store.setProviderHiddenFromMenuBar("a", hidden: false)
        XCTAssertFalse(store.isProviderHiddenFromMenuBar("a"))
        XCTAssertTrue(store.isPinned("a.m1"))

        XCTAssertTrue(store.undo())
        XCTAssertEqual(store.hiddenProviderIDs, hiddenBefore)
        XCTAssertEqual(store.pinnedMetricIDs, pinsBefore)
    }

    // MARK: - Fixtures

    private func makeStore(_ name: String) -> LayoutStore {
        LayoutStore(registry: makeRegistry(), defaults: makeDefaults(name), storageKey: "layout")
    }

    /// Four providers (a, b, c, d), each with three percent metrics m1/m2/m3, in registry order.
    private func makeRegistry() -> WidgetRegistry {
        let providers = ["a", "b", "c", "d"].map { id in
            Provider(id: id, displayName: id.uppercased(), icon: .providerMark("cursor"))
        }
        let descriptors = providers.flatMap { provider in
            (1...3).map { n in metric(provider, id: "\(provider.id).m\(n)", label: "M\(n)") }
        }
        return WidgetRegistry(providers: providers, descriptors: descriptors)
    }

    private func metric(_ provider: Provider, id: String, label: String) -> WidgetDescriptor {
        WidgetDescriptor(
            id: id,
            providerID: provider.id,
            metricLabel: label,
            sample: WidgetData(
                title: label,
                icon: provider.icon,
                kind: .percent,
                used: 10,
                limit: 100
            )
        )
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "OpenUsageTests.MenuBarHidden.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
