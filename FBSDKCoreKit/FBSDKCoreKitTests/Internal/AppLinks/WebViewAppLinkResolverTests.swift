// Copyright (c) 2014-present, Facebook, Inc. All rights reserved.
//
// You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
// copy, modify, and distribute this software in source code or binary form for use
// in connection with the web services and APIs provided by Facebook.
//
// As with any software that integrates with the Facebook platform, your use of
// this software is subject to the Facebook Developer Principles and Policies
// [http://developers.facebook.com/policy/]. This copyright notice shall be
// included in all copies or substantial portions of the software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import FBSDKCoreKit
import XCTest

// swiftlint:disable force_unwrapping
class WebViewAppLinkResolverTests: XCTestCase {

  var result: [AnyHashable: Any]?
  var error: Error?
  let data = "foo".data(using: .utf8)!
  var resolver: WebViewAppLinkResolver! // swiftlint:disable:this implicitly_unwrapped_optional
  let provider = TestSessionProvider()

  override func setUp() {
    super.setUp()

    resolver = WebViewAppLinkResolver(sessionProvider: provider)
  }

  // MARK: - Dependencies

  func testCreatingWithDefaults() {
    XCTAssertEqual(
      ObjectIdentifier(WebViewAppLinkResolver.shared.sessionProvider),
      ObjectIdentifier(URLSession.shared),
      "Should use the shared system session by default"
    )
  }

  func testCreatingWithSession() {
    XCTAssertEqual(
      ObjectIdentifier(resolver.sessionProvider),
      ObjectIdentifier(provider),
      "Should be able to create with a session provider"
    )
  }

  // MARK: - Redirecting

  func testFollowRedirectsURL() {
    let task = TestSessionDataTask()
    provider.stubbedDataTask = task
    resolver.followRedirects(SampleUrls.valid) { _, _ in }

    XCTAssertEqual(
      provider.capturedRequest?.url,
      SampleUrls.valid,
      "Should create a url request with the provided url"
    )
    XCTAssertEqual(
      provider.capturedRequest?.allHTTPHeaderFields?.contains { key, value in
        key == "Prefer-Html-Meta-Tags" && value == "al"
      },
      true,
      "Should include a header for which html meta tags to prefer"
    )
    XCTAssertEqual(
      task.resumeCallCount,
      1,
      "Should start the data task to follow redirects"
    )
  }

  func testFollowRedirectsWithErrorOnly() {
    resolver.followRedirects(SampleUrls.valid) { potentialResult, potentialError in
      self.result = potentialResult
      self.error = potentialError
    }

    provider.capturedCompletion?(nil, nil, SampleError())

    XCTAssertNil(
      result,
      "Should not call the redirect completion with a result if there is also an error"
    )
    XCTAssertTrue(
      error is SampleError,
      "Should call the completion with the error from the redirect"
    )
  }

  func testFollowRedirectWithHTTPResponseOnly() {
    resolver.followRedirects(SampleUrls.valid) { potentialResult, potentialError in
      self.result = potentialResult
      self.error = potentialError
    }

    provider.capturedCompletion?(
      nil,
      SampleHTTPURLResponses.validStatusCode,
      nil
    )

    XCTAssertNil(
      result,
      "Should not have a result if there is no response data"
    )
    XCTAssertEqual(
      error as NSError?,
      SDKError.unknownError(withMessage: "Invalid network response - missing data") as NSError,
      "Should call the completion with an error indicating the missing data"
    )
  }

  func testFollowRedirectsWithValidHTTPResponse() {
    resolver.followRedirects(SampleUrls.valid) { potentialResult, potentialError in
      self.result = potentialResult
      self.error = potentialError
    }

    provider.capturedCompletion?(
      data,
      SampleHTTPURLResponses.validStatusCode,
      nil
    )

    validateResult(
      result: result,
      data: data,
      response: SampleHTTPURLResponses.validStatusCode!,
      error: error
    )
  }

  func testFollowRedirectsWithRedirectingHTTPResponseMissingLocationURL() {
    // Just testing the upper and lower bounds
    [300, 399].forEach { code in
      provider.dataTaskCallCount = 0
      resolver.followRedirects(SampleUrls.valid) { potentialResult, potentialError in
        self.result = potentialResult
        self.error = potentialError
      }

      provider.capturedCompletion?(
        data,
        SampleHTTPURLResponses.valid(statusCode: code),
        nil
      )

      XCTAssertEqual(
        provider.dataTaskCallCount,
        2,
        "Should create a second data task for the url redirect"
      )
    }
  }

  func testFollowRedirectsWithRedirectingHTTPResponseIncludingLocationURL() {
    let redirectURL = SampleUrls.valid(path: "redirected")
    resolver.followRedirects(SampleUrls.valid) { potentialResult, potentialError in
      self.result = potentialResult
      self.error = potentialError
    }

    provider.capturedCompletion?(
      data,
      SampleHTTPURLResponses.valid(
        statusCode: 300,
        headerFields: ["Location": redirectURL.absoluteString]
      ),
      nil
    )

    XCTAssertEqual(
      provider.dataTaskCallCount,
      2,
      "Should create a second data task for the url redirect"
    )
    XCTAssertEqual(
      provider.capturedRequest?.url,
      redirectURL,
      "The second request should be to the redirect url"
    )
  }

  // MARK: - Helpers

  func validateResult(
    result: [AnyHashable: Any]?,
    data: Data,
    response: HTTPURLResponse,
    error: Error?,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      result?["response"] as? HTTPURLResponse,
      response,
      "Should include the http response in the result",
      file: file,
      line: line
    )
    XCTAssertEqual(
      result?["data"] as? Data,
      data,
      "Should include the data in the result",
      file: file,
      line: line
    )
    XCTAssertNil(
      error,
      "Should not call the completion with an error and a result",
      file: file,
      line: line
    )
  }
}
