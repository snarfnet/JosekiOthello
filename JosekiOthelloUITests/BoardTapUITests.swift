import XCTest

// 3D 盤を本物のタップで操作する。打つ → AI が返す、を定石から AI 対戦まで続け、戻る・真上・新しい対局も押す。
// 盤の升の位置は Board3DView のカメラ合わせから計算（真上のとき 1 升 ≒ 盤ビュー幅の 0.0995）。
final class BoardTapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var board: XCUIElement { app.descendants(matching: .any)["board3d"] }
    private func count(_ id: String) -> Int { Int(app.staticTexts[id].label) ?? -1 }
    private var total: Int { count("blackCount") + count("whiteCount") }
    private var myTurn: Bool { app.staticTexts["あなたの番"].exists }
    private var gameOver: Bool { ["あなたの勝ち!", "AIの勝ち", "引き分け"].contains { app.staticTexts[$0].exists } }

    private func tapCell(_ r: Int, _ c: Int) {
        let k = 0.0995
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + (Double(c) - 3.5) * k, dy: 0.5 + (Double(r) - 3.5) * k)).tap()
    }

    private func waitUntil(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return cond()
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("uitest-\(name).png"))
        }
    }

    // 盤の 64 升を順に叩き、石が増えたところで止める（打てない升・動きの最中のタップは無視される）
    @discardableResult
    private func playOneMove() -> (Int, Int)? {
        let before = total
        for r in 0..<8 { for c in 0..<8 {
            tapCell(r, c)
            if waitUntil(0.35, { total > before }) { return (r, c) }
        }}
        return nil
    }

    func testPlayByTapping() {
        XCTAssertTrue(board.waitForExistence(timeout: 10), "盤が出ない")
        XCTAssertEqual(count("blackCount"), 2); XCTAssertEqual(count("whiteCount"), 2)

        // 1 手目：d3（row 2, col 3）は初期局面で必ず打てる
        tapCell(2, 3)
        XCTAssertTrue(waitUntil(3) { self.count("blackCount") == 4 && self.count("whiteCount") == 1 }, "d3 のタップで石が置けない")
        XCTAssertTrue(waitUntil(8) { self.total == 6 && self.myTurn }, "AI（定石）が返さない")
        shot("1-after-first")

        // 戻る：2 手ぶん戻って初期局面
        sleep(2)
        app.buttons["戻る"].tap()
        XCTAssertTrue(waitUntil(5) { self.count("blackCount") == 2 && self.count("whiteCount") == 2 }, "戻るで初期局面に戻らない")

        // 傾ける → 「真上」ボタンが出る → 押すと消える
        board.swipeUp()
        XCTAssertTrue(app.buttons["真上"].waitForExistence(timeout: 3), "傾けても真上ボタンが出ない")
        shot("2-tilted")
        app.buttons["真上"].tap()
        XCTAssertTrue(waitUntil(3) { !self.app.buttons["真上"].exists }, "真上ボタンで戻らない")

        // 定石を抜けて AI 対戦まで打ち続ける
        var moves = 0
        while moves < 14 && !gameOver {
            XCTAssertTrue(waitUntil(20) { self.myTurn || self.gameOver }, "\(moves) 手目のあと自分の番にならない")
            if gameOver { break }
            sleep(2)   // 裏返しの動きが終わるまで
            let before = total
            guard let cell = playOneMove() else { shot("x-stuck"); XCTFail("\(moves + 1) 手目：どの升を叩いても打てない"); return }
            XCTAssertGreaterThan(total, before)
            print("move \(moves + 1): row \(cell.0) col \(cell.1) -> black \(count("blackCount")) white \(count("whiteCount"))")
            moves += 1
            if moves == 7 { shot("3-mid") }
        }
        XCTAssertTrue(waitUntil(20) { self.myTurn || self.gameOver })
        sleep(2)
        shot("4-after-\(moves)")
        XCTAssertTrue(app.staticTexts["AI対戦モード"].exists || gameOver, "AI 対戦まで進んでいない")

        // 新しい対局
        app.buttons["新しい対局"].tap()
        XCTAssertTrue(waitUntil(5) { self.count("blackCount") == 2 && self.count("whiteCount") == 2 }, "新しい対局で初期局面にならない")
        sleep(2)
        shot("5-new-game")
    }
}
