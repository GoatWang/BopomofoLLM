//
//  OllamaServiceTests.swift
//  McBopomofoTests
//
//  Created by WANG HSUAN CHUNG on 11/4/25.
//

import Foundation
import XCTest
@testable import McBopomofo

final class OllamaServiceTests: XCTestCase {

    func testGenerateCompletionReturnsSuggestion() {
        let expectation = self.expectation(description: "OllamaService generates a suggestion")
        let service = OllamaService(model: Preferences.autocompleteModel) // or your actual model
        let prompt = "今天"

        service.generateCompletion(context: prompt) { suggestion, error in
            XCTAssertNil(error, "Expected no error, got \(String(describing: error))")
            XCTAssertNotNil(suggestion, "Expected a suggestion, got nil")
            XCTAssertFalse(suggestion!.isEmpty, "Suggestion should not be empty")
            print("Suggestion: \(suggestion!)")

            expectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)
    }
}
