

import XCTest
@testable import LFColoringBook

class LFColoringBookTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testExample() throws {
    }

    func testPerformanceExample() throws {
        self.measure {
        }
    }
    
    func testRects(){
        
        let rect = CGRect(x: 0, y: 0,
                          width: 4, height: 4)
        
        XCTAssert(rect.contains(CGPoint(x: 0, y: 0)))
        XCTAssert(rect.contains(CGPoint(x: 1, y: 0)))
        XCTAssert(rect.contains(CGPoint(x: 2, y: 0)))
        XCTAssert(rect.contains(CGPoint(x: 3, y: 0)))
        XCTAssert(!rect.contains(CGPoint(x: 4, y: 0)))
    }
    


}
