import SwiftUI
import SceneKit

// カメラの状態。初期は真上から。ドラッグで傾け・回し、ピンチで寄る。「真上」ボタンで戻す
final class BoardCamera: ObservableObject {
    @Published var isTopDown = true
    fileprivate weak var coordinator: Board3DView.Coordinator?
    func resetToTop() { coordinator?.resetCamera(animated: true) }
}

struct Board3DView: UIViewRepresentable {
    @ObservedObject var game: OthelloGame
    @ObservedObject var camera: BoardCamera

    func makeCoordinator() -> Coordinator { Coordinator(game: game, camera: camera) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        let c = context.coordinator
        v.scene = c.board.scene
        v.pointOfView = c.cameraNode
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        v.preferredFramesPerSecond = 60
        v.isPlaying = true            // 動きの途中も描き続ける
        c.view = v
        v.isAccessibilityElement = true
        v.accessibilityIdentifier = "board3d"
        v.accessibilityLabel = "盤"
        camera.coordinator = c

        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let dbl = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTouchesRequired = 2       // 二本指ダブルタップで真上に戻す（一本指のタップは石を置くのに使う）
        dbl.numberOfTapsRequired = 2
        pan.delegate = c; pinch.delegate = c
        [tap, pan, pinch, dbl].forEach { v.addGestureRecognizer($0) }

        c.board.syncNow(c.cells(game))
        c.refreshMarks(game)
        c.board.onIdle = { [weak c] in c.map { $0.refreshMarks($0.game) } }
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.game = game
        c.board.push(c.cells(game))
        if !c.board.animating { c.refreshMarks(game) }
        c.layout()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var game: OthelloGame
        let camera: BoardCamera
        let board = Board3DScene()
        let cameraNode = SCNNode()
        weak var view: SCNView?
        // 視点（度）。pitch 90 = 真上
        private var yaw: Float = 0, pitch: Float = 90, zoom: Float = 1
        private var fitDist: Float = 0.7

        init(game: OthelloGame, camera: BoardCamera) {
            self.game = game; self.camera = camera
            super.init()
            let cam = SCNCamera()
            cam.fieldOfView = 30
            cam.zNear = 0.01; cam.zFar = 5
            cam.wantsHDR = true
            cam.wantsExposureAdaptation = false
            cam.exposureOffset = 0
            cam.bloomIntensity = 0.15; cam.bloomThreshold = 0.9
            cameraNode.camera = cam
            board.scene.rootNode.addChildNode(cameraNode)
            if ProcessInfo.processInfo.arguments.contains("-tilt") { pitch = 38; yaw = 0 }
            applyCamera()
        }

        func cells(_ g: OthelloGame) -> [Int] { g.board.flatMap { $0.map { $0.rawValue } } }

        func refreshMarks(_ g: OthelloGame) {
            let mine = g.currentPlayer == .black && !g.isAIThinking && !g.isGameOver
            let hints = mine ? Array(g.validMoveSet) : []
            let joseki = Set(g.isInJoseki ? g.availableJosekiBranches.map { $0.row * 8 + $0.col } : [])
            board.setHints(hints, joseki: joseki)
            board.setLastMove(g.lastMove.map { $0.0 * 8 + $0.1 })
        }

        // 盤の外枠がちょうど収まる距離（縦横の狭い方に合わせる）
        func layout() {
            guard let v = view, v.bounds.width > 0, let cam = cameraNode.camera else { return }
            let aspect = Float(v.bounds.width / v.bounds.height)
            let half = Board3DScene.outer * 0.5 * 1.04
            let vfov = Float(cam.fieldOfView) * .pi / 180
            let dV = half / tanf(vfov / 2)
            let hfov = 2 * atanf(tanf(vfov / 2) * aspect)
            let dH = half / tanf(hfov / 2)
            let d = max(dV, dH) + Board3DScene.baseH
            if abs(d - fitDist) > 0.0001 { fitDist = d; applyCamera() }
        }

        private func applyCamera() {
            let p = pitch * .pi / 180, y = yaw * .pi / 180
            let target = SIMD3<Float>(0, Board3DScene.baseH, 0)
            let dist = fitDist * zoom
            let pos = target + SIMD3(cosf(p) * sinf(y), sinf(p), cosf(p) * cosf(y)) * dist
            cameraNode.simdPosition = pos
            // 画面の上＝盤の奥（1 行目）。真上から見ても向きが決まるよう、水平の「奥」を上の手がかりにする
            cameraNode.simdLook(at: target, up: SIMD3(-sinf(y), 0, -cosf(y)), localFront: SIMD3(0, 0, -1))
            let top = pitch > 89.5 && abs(yaw) < 0.5 && abs(zoom - 1) < 0.01
            if camera.isTopDown != top { DispatchQueue.main.async { self.camera.isTopDown = top } }
        }

        func resetCamera(animated: Bool) {
            guard animated else { yaw = 0; pitch = 90; zoom = 1; applyCamera(); return }
            let y0 = yaw, p0 = pitch, z0 = zoom
            let dur = 0.35
            cameraNode.runAction(.customAction(duration: dur) { [weak self] _, el in
                guard let self = self else { return }
                let k = min(Float(el / CGFloat(dur)), 1); let e = 1 - powf(1 - k, 3)
                self.yaw = y0 + (0 - y0) * e; self.pitch = p0 + (90 - p0) * e; self.zoom = z0 + (1 - z0) * e
                self.applyCamera()
            })
        }

        // MARK: gestures

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = view else { return }
            guard game.currentPlayer == .black && !game.isAIThinking && !game.isGameOver && !board.animating else { return }
            guard let cell = cellAt(g.location(in: v), in: v) else { return }
            let (row, col) = (cell / 8, cell % 8)
            if game.makeMove(row: row, col: col) {
                if game.currentPlayer == .white && !game.isGameOver { game.scheduleAIMove() }
            }
        }

        // 画面の点からラシャ面（y = 盤面）への交点で升を求める
        private func cellAt(_ pt: CGPoint, in v: SCNView) -> Int? {
            let near = v.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 0))
            let far = v.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 1))
            let a = SIMD3<Float>(near.x, near.y, near.z), b = SIMD3<Float>(far.x, far.y, far.z)
            let planeY = board.root.simdWorldPosition.y
            let dir = b - a
            guard abs(dir.y) > 1e-6 else { return nil }
            let t = (planeY - a.y) / dir.y
            guard t > 0 else { return nil }
            let p = a + dir * t
            let col = Int(floorf(p.x / Board3DScene.cell + 4)), row = Int(floorf(p.z / Board3DScene.cell + 4))
            guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
            return row * 8 + col
        }

        private var lastPan = CGPoint.zero
        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = view else { return }
            let p = g.translation(in: v)
            if g.state == .began { lastPan = p; cameraNode.removeAllActions() }
            let d = CGPoint(x: p.x - lastPan.x, y: p.y - lastPan.y); lastPan = p
            let k = Float(600 / max(v.bounds.width, 1))
            yaw = max(-60, min(60, yaw - Float(d.x) * 0.25 * k))
            pitch = max(22, min(90, pitch + Float(d.y) * 0.25 * k))
            applyCamera()
        }

        private var pinchStart: Float = 1
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { pinchStart = zoom; cameraNode.removeAllActions() }
            zoom = max(0.45, min(1.6, pinchStart / Float(max(g.scale, 0.01))))
            applyCamera()
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) { resetCamera(animated: true) }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            (a is UIPanGestureRecognizer && b is UIPinchGestureRecognizer) || (a is UIPinchGestureRecognizer && b is UIPanGestureRecognizer)
        }
    }
}
