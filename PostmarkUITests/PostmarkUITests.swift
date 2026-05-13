//
//  PostmarkUITests.swift
//  PostmarkUITests
//
//  Created by Marcus Schmidt on 2026-04-14.
//

import XCTest

final class PostmarkUITests: XCTestCase {
    private let inboxFixtureArgument = "--uitest-inbox"
    private let paywallReadyArgument = "--uitest-paywall-ready"
    private let inboxMessageIdentifier = "inbox-message-uitest-msg-001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSwipeActionsReplyAndArchive() throws {
        let replyApp = launchInboxFixture()
        openMenuWindowIfNeeded(in: replyApp)
        let replyRow = inboxRow(in: replyApp)
        guard replyRow.waitForExistence(timeout: 12) else {
            XCTFail("Inbox row missing\n\(replyApp.debugDescription)")
            return
        }

        replyRow.swipeRight()
        let replyButton = replyApp.buttons["Reply"]
        XCTAssertTrue(replyButton.waitForExistence(timeout: 2))
        replyButton.tap()

        let replyHeader = replyApp.staticTexts["Reply to UI Test Sender"]
        XCTAssertTrue(replyHeader.waitForExistence(timeout: 3))
        replyApp.terminate()

        let archiveApp = launchInboxFixture()
        openMenuWindowIfNeeded(in: archiveApp)
        let archiveRow = inboxRow(in: archiveApp)
        guard archiveRow.waitForExistence(timeout: 12) else {
            XCTFail("Inbox row missing\n\(archiveApp.debugDescription)")
            return
        }

        archiveRow.swipeLeft()
        let archiveButton = archiveApp.buttons["Archive"]
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 2))
        archiveButton.tap()

        let rowHidden = NSPredicate(format: "exists == false")
        expectation(
            for: rowHidden,
            evaluatedWith: archiveRow,
            handler: nil
        )
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testAddAccountShowsPaywallWhenUnsubscribed() throws {
        let app = launchInboxFixture()
        openMenuWindowIfNeeded(in: app)

        let settingsButton = app.buttons["gearshape"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 4))
        settingsButton.tap()

        let addButton = app.buttons["Add account"]
        let upgradeButton = app.buttons["Upgrade"]
        let didFindAdd = addButton.waitForExistence(timeout: 2)
        let didFindUpgrade = upgradeButton.waitForExistence(timeout: 2)
        XCTAssertTrue(didFindAdd || didFindUpgrade)
        if didFindAdd {
            addButton.tap()
        } else {
            upgradeButton.tap()
        }

        let paywall = app.otherElements["paywall-view"]
        let paywallTitle = app.staticTexts["Unlock Postmark Pro"]
        let didFindPaywall = paywall.waitForExistence(timeout: 6)
            || paywallTitle.waitForExistence(timeout: 6)
        XCTAssertTrue(didFindPaywall)
    }

    @MainActor
    func testPaywallPurchaseTapKeepsMainWindowFlowActive() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            inboxFixtureArgument,
            paywallReadyArgument
        ]
        app.launch()
        openMenuWindowIfNeeded(in: app)

        let paywall = app.otherElements["paywall-view"]
        let paywallTitle = app.staticTexts["Unlock Postmark Pro"]
        let didFindPaywall = paywall.waitForExistence(timeout: 4)
            || paywallTitle.waitForExistence(timeout: 4)
        XCTAssertTrue(didFindPaywall)

        let trialButton = app.buttons["Start free trial"]
        let purchaseLabelButton = app.buttons["Purchase"]
        let didFindPurchaseButton = trialButton.waitForExistence(timeout: 2)
            || purchaseLabelButton.waitForExistence(timeout: 2)
        XCTAssertTrue(didFindPurchaseButton)
        let purchaseButton = trialButton.exists ? trialButton : purchaseLabelButton
        purchaseButton.tap()

        let purchasingButton = app.buttons["Purchasing..."]
        let purchasingState = app.descendants(matching: .any)["Purchasing..."]
        let didEnterPurchasing = purchasingButton.waitForExistence(timeout: 3)
            || purchasingState.waitForExistence(timeout: 3)
        XCTAssertTrue(didEnterPurchasing)
        XCTAssertTrue(paywall.exists || paywallTitle.exists)
    }

    private func launchInboxFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [inboxFixtureArgument]
        app.launch()
        return app
    }

    private func openMenuWindowIfNeeded(in app: XCUIApplication) {
        let inboxList = app.descendants(matching: .any)["inbox-list"]
        if inboxList.waitForExistence(timeout: 1.5) {
            return
        }
        let statusItem = app.menuBars.statusItems["Postmark"]
        if statusItem.waitForExistence(timeout: 4) {
            statusItem.click()
        }
    }

    private func inboxRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons[inboxMessageIdentifier]
    }
}
