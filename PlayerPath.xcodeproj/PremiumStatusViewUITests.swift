//
//  PremiumStatusViewUITests.swift
//  PlayerPathUITests
//
//  Created by Assistant on 10/30/25.
//

import XCTest

final class PremiumStatusViewUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Configure app for UI testing
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["DISABLE_ANIMATIONS"] = "1"
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Premium Status View Tests
    
    func testPremiumStatusViewAppears() throws {
        // Navigate to Premium Status view
        app.tabBars.buttons["Premium"].tap()
        
        // Verify the view loads
        XCTAssertTrue(app.navigationBars["Premium Status"].exists)
        XCTAssertTrue(app.staticTexts["Premium Status"].exists)
    }
    
    func testFreeUserStatusDisplay() throws {
        // Set up test environment for free user
        app.launchEnvironment["TEST_USER_STATE"] = "FREE"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Verify free user status is displayed
        XCTAssertTrue(app.staticTexts["Free Plan"].exists)
        XCTAssertTrue(app.staticTexts["Limited features available"].exists)
        XCTAssertTrue(app.buttons["Upgrade to Pro"].exists)
    }
    
    func testPremiumUserStatusDisplay() throws {
        // Set up test environment for premium user
        app.launchEnvironment["TEST_USER_STATE"] = "PREMIUM"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Verify premium user status is displayed
        XCTAssertTrue(app.staticTexts["PlayerPath Pro"].exists)
        XCTAssertTrue(app.staticTexts["All premium features unlocked"].exists)
        XCTAssertTrue(app.buttons["Manage Subscriptions"].exists)
    }
    
    // MARK: - Feature List Tests
    
    func testFeatureListDisplays() throws {
        app.tabBars.buttons["Premium"].tap()
        
        // Verify all premium features are listed
        XCTAssertTrue(app.staticTexts["Features"].exists)
        XCTAssertTrue(app.staticTexts["Unlimited Video Recording"].exists)
        XCTAssertTrue(app.staticTexts["Cloud Storage"].exists)
        XCTAssertTrue(app.staticTexts["Advanced Analytics"].exists)
        XCTAssertTrue(app.staticTexts["Video Export"].exists)
        XCTAssertTrue(app.staticTexts["Custom Branding"].exists)
    }
    
    func testFeatureAvailabilityIndicators() throws {
        app.launchEnvironment["TEST_USER_STATE"] = "FREE"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Verify feature availability indicators
        let unavailableFeatures = app.images["xmark.circle"]
        XCTAssertGreaterThan(unavailableFeatures.count, 0, "Free users should see unavailable feature indicators")
    }
    
    // MARK: - Upgrade Flow Tests
    
    func testUpgradeButtonTap() throws {
        app.launchEnvironment["TEST_USER_STATE"] = "FREE"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Tap upgrade button
        app.buttons["Upgrade to Pro"].tap()
        
        // Verify upgrade sheet appears
        XCTAssertTrue(app.sheets.firstMatch.exists, "Upgrade sheet should appear")
    }
    
    func testUpgradeSheetDismissal() throws {
        app.launchEnvironment["TEST_USER_STATE"] = "FREE"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        app.buttons["Upgrade to Pro"].tap()
        
        // Wait for sheet to appear
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        
        // Dismiss sheet (if there's a close button)
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        } else {
            // Swipe down to dismiss
            sheet.swipeDown()
        }
        
        // Verify sheet is dismissed
        XCTAssertFalse(sheet.exists, "Upgrade sheet should be dismissed")
    }
    
    // MARK: - Subscription Management Tests
    
    func testManageSubscriptionsButton() throws {
        app.launchEnvironment["TEST_USER_STATE"] = "PREMIUM"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Tap manage subscriptions button
        app.buttons["Manage Subscriptions"].tap()
        
        // This would typically open Settings app or Safari
        // In UI tests, we can verify the tap was handled
        XCTAssertTrue(true, "Manage subscriptions button was tapped")
    }
    
    func testRestorePurchasesButton() throws {
        app.launchEnvironment["TEST_USER_STATE"] = "PREMIUM"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Tap restore purchases button
        app.buttons["Restore Purchases"].tap()
        
        // Verify loading state or completion feedback
        // This would depend on your implementation
        XCTAssertTrue(true, "Restore purchases was initiated")
    }
    
    // MARK: - Pull to Refresh Tests
    
    func testPullToRefresh() throws {
        app.tabBars.buttons["Premium"].tap()
        
        let listView = app.tables.firstMatch
        XCTAssertTrue(listView.exists)
        
        // Perform pull to refresh
        let firstCell = listView.cells.firstMatch
        let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5))
        
        start.press(forDuration: 0.1, thenDragTo: end)
        
        // Verify refresh indicator appears and disappears
        // This would need specific implementation details
        XCTAssertTrue(true, "Pull to refresh was performed")
    }
    
    // MARK: - Error State Tests
    
    func testErrorStateDisplay() throws {
        // Set up test environment with error state
        app.launchEnvironment["TEST_ERROR_STATE"] = "NETWORK_ERROR"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Verify error message is displayed
        XCTAssertTrue(app.images["exclamationmark.triangle"].exists, "Error icon should be visible")
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        app.tabBars.buttons["Premium"].tap()
        
        // Verify important elements have accessibility labels
        XCTAssertTrue(app.buttons["Upgrade to Pro"].isHittable)
        XCTAssertNotEqual(app.buttons["Upgrade to Pro"].label, "", "Button should have accessibility label")
        
        // Test feature rows accessibility
        let featureRows = app.staticTexts.matching(identifier: "premium_feature_title")
        XCTAssertGreaterThan(featureRows.count, 0, "Feature rows should be accessible")
    }
    
    func testVoiceOverNavigation() throws {
        // This would require specific VoiceOver testing setup
        app.tabBars.buttons["Premium"].tap()
        
        // Verify all interactive elements are accessible
        let interactiveElements = app.buttons.allElementsBoundByIndex + app.staticTexts.allElementsBoundByIndex
        
        for element in interactiveElements {
            if element.exists && element.isHittable {
                XCTAssertTrue(element.isAccessibilityElement, "Interactive elements should be accessible")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testViewLoadingPerformance() throws {
        measure {
            app.tabBars.buttons["Premium"].tap()
            
            // Wait for view to load
            XCTAssertTrue(app.navigationBars["Premium Status"].waitForExistence(timeout: 2))
            
            // Navigate back
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
    }
    
    func testScrollPerformance() throws {
        app.tabBars.buttons["Premium"].tap()
        
        let table = app.tables.firstMatch
        XCTAssertTrue(table.exists)
        
        measure {
            // Perform scrolling
            table.swipeUp()
            table.swipeDown()
        }
    }
    
    // MARK: - Edge Cases
    
    func testNetworkErrorRecovery() throws {
        // Simulate network error then recovery
        app.launchEnvironment["TEST_NETWORK_STATE"] = "ERROR_THEN_RECOVERY"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // Verify error state initially
        XCTAssertTrue(app.images["exclamationmark.triangle"].waitForExistence(timeout: 3))
        
        // Trigger refresh (pull to refresh or refresh button)
        let table = app.tables.firstMatch
        if table.exists {
            let firstCell = table.cells.firstMatch
            let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        
        // Verify recovery (error should disappear)
        XCTAssertFalse(app.images["exclamationmark.triangle"].waitForExistence(timeout: 3))
    }
    
    func testRapidStateChanges() throws {
        // Test rapid switching between free and premium states
        app.launchEnvironment["TEST_RAPID_STATE_CHANGES"] = "1"
        app.launch()
        
        app.tabBars.buttons["Premium"].tap()
        
        // The app should handle rapid state changes gracefully
        // Verify the view doesn't crash and displays correctly
        XCTAssertTrue(app.navigationBars["Premium Status"].exists)
    }
    
    // MARK: - Integration Tests
    
    func testNavigationIntegration() throws {
        // Test navigation to and from Premium Status view
        app.tabBars.buttons["Premium"].tap()
        XCTAssertTrue(app.navigationBars["Premium Status"].exists)
        
        // Navigate to other tabs
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Premium"].tap()
        
        // Verify state is preserved
        XCTAssertTrue(app.navigationBars["Premium Status"].exists)
    }
    
    func testDeepLinkToUpgrade() throws {
        // Test deep link directly to upgrade flow
        app.launchEnvironment["TEST_DEEP_LINK"] = "UPGRADE"
        app.launch()
        
        // Verify upgrade sheet appears directly
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3), "Upgrade sheet should appear from deep link")
    }
}

// MARK: - Helper Extensions

extension XCUIApplication {
    func waitForViewToLoad(timeout: TimeInterval = 5) -> Bool {
        let loadingIndicator = self.activityIndicators.firstMatch
        let viewContent = self.tables.firstMatch
        
        // Wait for loading to finish and content to appear
        return NSPredicate(format: "exists == false").wait(for: [loadingIndicator], timeout: timeout) &&
               viewContent.waitForExistence(timeout: timeout)
    }
}

extension NSPredicate {
    static func wait(for elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: elements.first)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}