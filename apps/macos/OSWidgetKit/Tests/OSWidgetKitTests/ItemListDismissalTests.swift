import CoreGraphics
import Testing
@testable import OSWidgetKit

@Suite("ItemListDismissal")
struct ItemListDismissalTests {
    private let icon = CGRect(x: 860, y: 950, width: 30, height: 24)

    @Test func clickInAnotherAppClosesTheList() {
        #expect(ItemListDismissal.closesList(clickAt: CGPoint(x: 400, y: 500), iconFrame: icon))
    }

    @Test func clickOnTheIconLeavesTheToggleToTheIcon() {
        #expect(!ItemListDismissal.closesList(clickAt: CGPoint(x: 875, y: 960), iconFrame: icon))
    }

    @Test func clickNextToTheIconClosesTheList() {
        #expect(ItemListDismissal.closesList(clickAt: CGPoint(x: 895, y: 960), iconFrame: icon))
    }

    @Test func clickClosesTheListWhenTheIconIsNotOnScreen() {
        #expect(ItemListDismissal.closesList(clickAt: CGPoint(x: 875, y: 960), iconFrame: nil))
    }

    @Test func reasonsLogInSnakeCase() {
        #expect(ItemListDismissal.Reason.resignActive.rawValue == "resign_active")
        #expect(ItemListDismissal.Reason.outsideClick.rawValue == "outside_click")
    }
}
