import XCTest
@testable import UDPMsg

extension Data {
  public init(fromString: String) {
    self = fromString.withCString { pointer -> Data in
      let buffer = UnsafeBufferPointer.init(start: pointer, count: fromString.count)
      return Data.init(buffer: buffer)
    }
  }
  public func toString() -> String {
    return self.withUnsafeBytes { (p: UnsafePointer<Int8>) -> String in
      return String.init(cString: p)
    }
  }
}

final class UDPMsgTests: XCTestCase {
  static var allTests = [
    ("testExample", testExample),
    ("testDomain", testDomain)
    ]

  func testDomain() {
    let _ = UDPMsg.setupAddress(domain: "store.ubiqweus.com", port: 6379)
  }
  
  func testExample() {
    let exp = expectation(description: "generalTest")
    let greetings = "Hello, world!"
    var total = 0
    let objective = 100
    do {
      let server = try UDPMsg()
      try server.run { server, data, address in
        let result = data.toString()
        XCTAssertEqual(result, greetings)
        print("received: ", result, total)
        total += 1
        if total >= objective {
          exp.fulfill()
        }
      }
      let address = UDPMsg.setupAddress(ip: "127.0.0.1", port: 6379)
      for _ in 0..<objective {
        _ = server.send(to: address, with: Data.init(fromString: greetings))
      }
      #if os(Linux)
      waitForExpectations(timeout: 5, handler: nil)
      #else
      wait(for: [exp], timeout: 5)
      #endif
    } catch (let err) {
      XCTFail("\(err)")
    }

  }

}
