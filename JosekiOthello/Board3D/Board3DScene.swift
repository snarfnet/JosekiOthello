import SceneKit
import UIKit
import AVFoundation

// 『恋のしろくろ』の写実 3D 盤を SceneKit に移したもの。
// 寸法は実物（升 34.5mm、駒 直径 29.4mm 厚 4.8mm）。胡桃の枠＋緑ラシャ、駒は樹脂のクリアコート。
// 置く・裏返す動きは手で打った感じに寄せる（置いた駒から遠い順に少しずつ遅れて返る）。
// 座標：x = 列（a→h）、z = 行（1→8）。真上から見ると 1 行目が画面の上。
final class Board3DScene {
    static let cell: Float = 0.0345, discR: Float = 0.0147, discH: Float = 0.0048
    static let fieldHalf = cell * 4, rimW: Float = 0.024, baseH: Float = 0.018, rimH: Float = 0.008
    static var outer: Float { fieldHalf * 2 + rimW * 2 }

    let scene = SCNScene()
    let root = SCNNode()            // ラシャ面の高さ。駒・ヒントはここに置く
    private var discs: [SCNNode] = []
    private var aos: [SCNNode] = []
    private var colors = [Int](repeating: 0, count: 64)   // 1 黒 2 白（表を向いている色）
    private var rests = [simd_quatf](repeating: simd_quatf(angle: 0, axis: [0, 1, 0]), count: 64)
    private var restPos = [SIMD3<Float>](repeating: .zero, count: 64)
    private var hintNodes: [SCNNode] = []
    private let lastMark = SCNNode()
    private var queue: [[Int]] = []
    private var lastPushed: [Int] = []
    private(set) var animating = false
    var onIdle: (() -> Void)?
    private let sfx = Sfx()

    init() {
        buildLights()
        buildBoard()
        buildDiscs()
    }

    // MARK: - 素材

    private static func image(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func pbr(_ albedo: String?, tint: UIColor = .white, rough: Float, normal: String? = nil, normalScale: CGFloat = 1, tiling: Float = 1, tileY: Float? = nil, roughMap: String? = nil, coat: CGFloat = 0, coatRough: CGFloat = 0.05) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // 色味はテクスチャに焼き込み済み（multiply は光を当てた後にかかるので使わない）
        if let a = albedo, let img = image(a) { m.diffuse.contents = img } else { m.diffuse.contents = tint }
        m.metalness.contents = 0.0
        if let r = roughMap, let img = image(r) { m.roughness.contents = img } else { m.roughness.contents = NSNumber(value: rough) }
        if let n = normal, let img = image(n) { m.normal.contents = img; m.normal.intensity = normalScale }
        if tiling != 1 || tileY != nil {
            let t = SCNMatrix4MakeScale(tiling, tileY ?? tiling, 1)
            for p in [m.diffuse, m.normal, m.roughness] { p.contentsTransform = t; p.wrapS = .repeat; p.wrapT = .repeat }
        }
        for p in [m.diffuse, m.normal, m.roughness] { p.mipFilter = .linear; p.maxAnisotropy = 8 }
        if coat > 0 { m.clearCoat.contents = NSNumber(value: Double(coat)); m.clearCoatRoughness.contents = NSNumber(value: Double(coatRough)) }
        return m
    }

    private static func unlitAlpha(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        var a: CGFloat = 1
        color.getRed(nil, green: nil, blue: nil, alpha: &a)
        m.diffuse.contents = color.withAlphaComponent(1)
        m.transparent.contents = image("soft_dot.png")
        m.transparencyMode = .aOne
        m.transparency = a
        m.writesToDepthBuffer = false
        return m
    }

    // MARK: - 光

    private func buildLights() {
        scene.background.contents = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        scene.lightingEnvironment.contents = Board3DScene.environmentImage()
        scene.lightingEnvironment.intensity = 1.15

        // 斜め上からの主光。駒の影を短く落とす
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 8
        key.shadowRadius = 2.5
        key.shadowColor = UIColor(white: 0, alpha: 0.45)
        key.orthographicScale = 0.25
        key.zNear = 0.01; key.zFar = 3
        let keyNode = SCNNode(); keyNode.light = key
        keyNode.position = SCNVector3(-0.35, 1.0, 0.3)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)
    }

    // 天井の蛍光灯と窓を思わせる明るい帯を入れた正距円筒の環境光。クリアコートに映り込む
    private static func environmentImage() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(white: 0.32, alpha: 1).cgColor, UIColor(red: 0.42, green: 0.4, blue: 0.37, alpha: 1).cgColor, UIColor(red: 0.1, green: 0.09, blue: 0.08, alpha: 1).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            cg.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
            for i in 0..<4 { cg.fill(CGRect(x: 30 + CGFloat(i) * 128, y: 14, width: 80, height: 12)) }  // 蛍光灯
            cg.setFillColor(UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 70, width: 60, height: 50))                                     // 窓
        }
    }

    // MARK: - 盤

    private func buildBoard() {
        let S = Board3DScene.self
        let board = SCNNode(); scene.rootNode.addChildNode(board)
        // 胡桃：木目は 12cm で一巡。横の枠は 90° 回した画像で、木目を長手方向に通す
        func walnut(_ horiz: Bool, _ w: Float, _ l: Float) -> SCNMaterial {
            S.pbr(horiz ? "walnut_h.jpg" : "walnut.jpg", rough: 0.42, normal: "wood_normal.jpg", normalScale: 0.35, tiling: w / 0.12, tileY: l / 0.12, coat: 0.35, coatRough: 0.2)
        }
        let outer = CGFloat(S.outer)
        let base = SCNBox(width: outer, height: CGFloat(S.baseH), length: outer, chamferRadius: 0.0025)
        base.materials = [walnut(false, S.outer, S.outer)]
        let baseNode = SCNNode(geometry: base); baseNode.position = SCNVector3(0, S.baseH * 0.5 - 0.0012, 0)
        board.addChildNode(baseNode)

        // 盤の下の柔らかい接地影
        for (k, a) in [(1.12, 0.55), (1.3, 0.35)] {
            let q = SCNPlane(width: outer * CGFloat(k), height: outer * CGFloat(k)); q.materials = [S.unlitAlpha(UIColor(white: 0, alpha: CGFloat(a)))]
            let n = SCNNode(geometry: q); n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(0, 0.0003, 0); n.renderingOrder = 10; n.castsShadow = false
            board.addChildNode(n)
        }

        let rimC = S.fieldHalf + S.rimW * 0.5
        for i in 0..<4 {
            let horiz = i < 2; let s: Float = i % 2 == 0 ? -1 : 1
            let box = horiz ? SCNBox(width: outer, height: CGFloat(S.rimH), length: CGFloat(S.rimW), chamferRadius: 0.0025)
                            : SCNBox(width: CGFloat(S.rimW), height: CGFloat(S.rimH), length: CGFloat(S.fieldHalf * 2), chamferRadius: 0.0025)
            box.materials = [horiz ? walnut(true, S.outer, S.rimW) : walnut(false, S.rimW, S.fieldHalf * 2)]
            let n = SCNNode(geometry: box)
            n.position = horiz ? SCNVector3(0, S.baseH + S.rimH * 0.5, rimC * s) : SCNVector3(rimC * s, S.baseH + S.rimH * 0.5, 0)
            board.addChildNode(n)
        }

        let felt = S.pbr("felt.jpg", rough: 0.88, normal: "felt_normal.jpg", normalScale: 1.2, tiling: 3.5)
        let fq = SCNPlane(width: CGFloat(S.fieldHalf * 2), height: CGFloat(S.fieldHalf * 2)); fq.materials = [felt]
        let fn = SCNNode(geometry: fq); fn.eulerAngles.x = -.pi / 2; fn.position = SCNVector3(0, S.baseH + 0.0004, 0)
        board.addChildNode(fn)

        root.position = SCNVector3(0, S.baseH + 0.0006, 0)
        board.addChildNode(root)

        // 罫線と星（印刷の黒、つや消し）
        let ink = S.pbr(nil, tint: UIColor(white: 0.045, alpha: 1), rough: 0.8)
        for i in 1..<8 {
            let o = -S.fieldHalf + Float(i) * S.cell
            for horiz in [false, true] {
                let p = SCNPlane(width: horiz ? CGFloat(S.fieldHalf * 2) : 0.001, height: horiz ? 0.001 : CGFloat(S.fieldHalf * 2)); p.materials = [ink]
                let n = SCNNode(geometry: p); n.eulerAngles.x = -.pi / 2
                n.position = horiz ? SCNVector3(0, 0.0001, o) : SCNVector3(o, 0.0001, 0)
                root.addChildNode(n)
            }
        }
        for i in [2, 6] { for j in [2, 6] {
            let c = SCNCylinder(radius: 0.0022, height: 0.0003); c.radialSegmentCount = 24; c.materials = [ink]
            let n = SCNNode(geometry: c); n.position = SCNVector3(-S.fieldHalf + Float(i) * S.cell, 0.00015, -S.fieldHalf + Float(j) * S.cell)
            root.addChildNode(n)
        }}

        // 最後に打った駒の上の小さな印
        let dot = SCNCylinder(radius: 0.0022, height: 0.0002); dot.radialSegmentCount = 24
        let dm = SCNMaterial(); dm.lightingModel = .constant; dm.diffuse.contents = UIColor(red: 0.94, green: 0.53, blue: 0.24, alpha: 1)
        dot.materials = [dm]; lastMark.geometry = dot; lastMark.isHidden = true; lastMark.castsShadow = false
        root.addChildNode(lastMark)
    }

    // MARK: - 駒

    private func buildDiscs() {
        let S = Board3DScene.self
        let geo = DiscGeometry.make(R: S.discR, h: S.discH, bevel: 0.0011, seg: 96)
        let white = S.pbr("disc_white.png", rough: 0.1, normal: "disc_normal.jpg", normalScale: 0.5, roughMap: "disc_rough.png", coat: 0.7, coatRough: 0.04)
        let black = S.pbr("disc_black.png", rough: 0.1, normal: "disc_normal.jpg", normalScale: 0.6, roughMap: "disc_rough.png", coat: 0.8, coatRough: 0.03)
        geo.materials = [white, black]   // 上半分＝白、下半分＝黒
        let aoMat = S.unlitAlpha(UIColor(white: 0, alpha: 0.55))
        let aoGeo = SCNPlane(width: CGFloat(S.discR * 2.5), height: CGFloat(S.discR * 2.5)); aoGeo.materials = [aoMat]
        for i in 0..<64 {
            let n = SCNNode(geometry: geo); n.castsShadow = true; n.isHidden = true
            root.addChildNode(n); discs.append(n)
            let a = SCNNode(geometry: aoGeo); a.eulerAngles.x = -.pi / 2; a.renderingOrder = 11; a.castsShadow = false
            a.simdPosition = cellPos(i % 8, i / 8) - SIMD3(0, S.discH * 0.5 - 0.0003, 0); a.isHidden = true
            root.addChildNode(a); aos.append(a)
        }
    }

    func cellPos(_ col: Int, _ row: Int) -> SIMD3<Float> {
        SIMD3((Float(col) - 3.5) * Board3DScene.cell, Board3DScene.discH * 0.5, (Float(row) - 3.5) * Board3DScene.cell)
    }
    private static func orient(_ color: Int, yaw: Float) -> simd_quatf {
        let y = simd_quatf(angle: yaw, axis: [0, 1, 0])
        return color == 2 ? y : y * simd_quatf(angle: .pi, axis: [1, 0, 0])
    }
    private static func jitter(_ seed: Int) -> SIMD3<Float> {
        var g = SeededRandom(seed: UInt64(seed * 7919 + 13))
        return SIMD3((Float(g.next()) - 0.5) * 0.0018, 0, (Float(g.next()) - 0.5) * 0.0018)
    }
    private func setAo(_ i: Int, _ k: Float) {
        aos[i].isHidden = k <= 0.01
        aos[i].opacity = CGFloat(k)
    }

    // MARK: - 状態の反映

    /// 盤面（64 要素、0 空 1 黒 2 白）を渡す。1 手ぶんの差なら打つ動き、それ以外は即座に置き換える。
    func push(_ cells: [Int]) {
        if cells == lastPushed { return }
        lastPushed = cells
        queue.append(cells)
        if !animating { next() }
    }

    func syncNow(_ cells: [Int]) {
        queue.removeAll(); lastPushed = cells
        for i in 0..<64 { apply(i, cells[i]) }
    }

    private func apply(_ i: Int, _ c: Int) {
        colors[i] = c
        discs[i].isHidden = c == 0; setAo(i, c == 0 ? 0 : 1)
        guard c != 0 else { return }
        restPos[i] = cellPos(i % 8, i / 8) + Board3DScene.jitter(i)
        rests[i] = Board3DScene.orient(c, yaw: Float.random(in: 0..<(2 * .pi))) * simd_quatf(angle: Float.random(in: -0.007...0.007), axis: [1, 0, 0])
        discs[i].simdPosition = restPos[i]; discs[i].simdOrientation = rests[i]
    }

    private func next() {
        guard !queue.isEmpty else { animating = false; onIdle?(); return }
        let target = queue.removeFirst()
        var added: [Int] = [], removed = 0, changed: [Int] = []
        for i in 0..<64 {
            if colors[i] == 0 && target[i] != 0 { added.append(i) }
            else if colors[i] != 0 && target[i] == 0 { removed += 1 }
            else if colors[i] != target[i] { changed.append(i) }
        }
        if added.count == 1 && removed == 0 && !changed.isEmpty && changed.allSatisfy({ target[$0] == target[added[0]] }) {
            animating = true
            place(added[0], color: target[added[0]], flips: changed) { [weak self] in self?.next() }
        } else {
            for i in 0..<64 { if colors[i] != target[i] { apply(i, target[i]) } }
            next()
        }
    }

    func setLastMove(_ idx: Int?) {
        guard let i = idx, colors[i] != 0 else { lastMark.isHidden = true; return }
        lastMark.isHidden = false
        lastMark.simdPosition = restPos[i] + SIMD3(0, Board3DScene.discH * 0.5 + 0.0002, 0)
    }

    /// 打てる升の淡い光。定石の手は橙で強めに
    func setHints(_ cells: [Int], joseki: Set<Int>) {
        hintNodes.forEach { $0.removeFromParentNode() }; hintNodes.removeAll()
        let S = Board3DScene.self
        for c in cells {
            let isJ = joseki.contains(c)
            let q = SCNPlane(width: CGFloat(S.discR * (isJ ? 1.9 : 1.5)), height: CGFloat(S.discR * (isJ ? 1.9 : 1.5)))
            q.materials = [S.unlitAlpha(isJ ? UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.7) : UIColor(red: 1, green: 1, blue: 0.9, alpha: 0.3))]
            let n = SCNNode(geometry: q); n.eulerAngles.x = -.pi / 2; n.renderingOrder = 12; n.castsShadow = false
            n.simdPosition = cellPos(c % 8, c / 8) - SIMD3(0, S.discH * 0.5 - 0.0004, 0)
            root.addChildNode(n); hintNodes.append(n)
        }
    }

    // MARK: - 動き

    private static func cheb(_ a: Int, _ b: Int) -> Int { max(abs(a % 8 - b % 8), abs(a / 8 - b / 8)) }

    private func place(_ idx: Int, color: Int, flips: [Int], done: @escaping () -> Void) {
        hintNodes.forEach { $0.isHidden = true }
        lastMark.isHidden = true
        colors[idx] = color
        let d = discs[idx]; d.isHidden = false
        restPos[idx] = cellPos(idx % 8, idx / 8) + Board3DScene.jitter(idx + 64 * (flips.count + 1))
        rests[idx] = Board3DScene.orient(color, yaw: Float.random(in: 0..<(2 * .pi))) * simd_quatf(angle: Float.random(in: -0.009...0.009), axis: [1, 0, 0])
        let fromFar = color == 2       // 白（AI）は奥から、黒（あなた）は手前から
        drop(idx, fromFar: fromFar) { [weak self] in
            guard let self = self else { return }
            self.setAo(idx, 1); self.sfx.place()
            self.flash(idx)
            let order = flips.sorted { Board3DScene.cheb($0, idx) < Board3DScene.cheb($1, idx) }
            var running = order.count
            for f in order {
                let delay = Double(Board3DScene.cheb(f, idx)) * 0.075
                self.flipOne(f, from: idx, delay: delay) {
                    running -= 1
                    if running == 0 { done() }
                }
            }
        }
    }

    private func drop(_ i: Int, fromFar: Bool, done: @escaping () -> Void) {
        let d = discs[i]
        let side: Float = fromFar ? -1 : 1     // 奥は -z
        let rest = restPos[i], rq = rests[i]
        let start = rest + SIMD3(-side * 0.02, 0.11, side * 0.05)
        let tilt = simd_quatf(angle: side * 22 * .pi / 180, axis: [1, 0, 0]) * simd_quatf(angle: side * 6 * .pi / 180, axis: [0, 0, 1]) * rq
        d.simdPosition = start; d.simdOrientation = tilt; setAo(i, 0)
        let dur = 0.30
        let fall = SCNAction.customAction(duration: dur) { [weak self] node, el in
            let t = Float(el / CGFloat(dur)); let e = powf(min(t, 1), 1.8)
            node.simdPosition = simd_mix(start, rest, SIMD3(repeating: e))
            node.simdOrientation = simd_slerp(tilt, rq, powf(min(t, 1), 1.2))
            self?.setAo(i, max(0, min(1, (e - 0.6) / 0.4)))
        }
        let bd = 0.09
        let bounce = SCNAction.customAction(duration: bd) { node, el in
            let t = Float(el / CGFloat(bd))
            node.simdPosition = rest + SIMD3(0, sinf(min(t, 1) * .pi) * 0.0012, 0)
        }
        d.runAction(.sequence([fall, bounce])) {
            DispatchQueue.main.async { d.simdPosition = rest; d.simdOrientation = rq; done() }
        }
    }

    private func flipOne(_ i: Int, from: Int, delay: Double, done: @escaping () -> Void) {
        let d = discs[i]
        var dir = restPos[i] - cellPos(from % 8, from / 8); dir.y = 0
        let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), simd_normalize(dir)))
        let start = rests[i], end = simd_quatf(angle: .pi, axis: axis) * start
        colors[i] = colors[i] == 1 ? 2 : 1
        let rest = restPos[i]
        let lift = Board3DScene.discR * 1.08 + 0.0015
        let dur = 0.34
        let flip = SCNAction.customAction(duration: dur) { [weak self] node, el in
            let k = min(Float(el / CGFloat(dur)), 1)
            let e = k < 0.5 ? 2 * k * k : 1 - powf(-2 * k + 2, 2) / 2
            node.simdOrientation = simd_quatf(angle: .pi * e, axis: axis) * start
            node.simdPosition = rest + SIMD3(0, sinf(k * .pi) * lift, 0)
            self?.setAo(i, 1 - sinf(k * .pi) * 0.8)
        }
        d.runAction(.sequence([.wait(duration: delay), flip])) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.rests[i] = end; d.simdOrientation = end; d.simdPosition = rest; self.setAo(i, 1)
                self.sfx.flip()
                done()
            }
        }
    }

    // 置いた升に広がる淡い光の輪
    private func flash(_ i: Int) {
        let S = Board3DScene.self
        let q = SCNPlane(width: CGFloat(S.discR * 2), height: CGFloat(S.discR * 2))
        q.materials = [S.unlitAlpha(UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.5))]
        let n = SCNNode(geometry: q); n.eulerAngles.x = -.pi / 2; n.renderingOrder = 13; n.castsShadow = false
        n.simdPosition = cellPos(i % 8, i / 8) - SIMD3(0, S.discH * 0.5 - 0.0008, 0)
        root.addChildNode(n)
        let dur = 0.45
        n.runAction(.sequence([.customAction(duration: dur) { node, el in
            let k = min(Float(el / CGFloat(dur)), 1)
            node.simdScale = SIMD3(repeating: 1 + k * 1.8)
            node.opacity = CGFloat(1 - k)
        }, .removeFromParentNode()]))
    }
}

// MARK: - 駒の形（縁を丸めた円盤。上半分と下半分で別の素材）

enum DiscGeometry {
    static func make(R: Float, h: Float, bevel: Float, seg: Int) -> SCNGeometry {
        var prof: [SIMD4<Float>] = []   // (r, y, nr, ny) 上から下へ
        let hh = h * 0.5, bs = 8
        prof.append([0, hh, 0, 1]); prof.append([R - bevel, hh, 0, 1])
        for i in 1...bs { let a = Float(i) / Float(bs) * .pi * 0.5; prof.append([R - bevel + sinf(a) * bevel, hh - bevel + cosf(a) * bevel, sinf(a), cosf(a)]) }
        prof.append([R, 0, 1, 0])
        for i in 0...bs { let a = Float(i) / Float(bs) * .pi * 0.5; prof.append([R - bevel + cosf(a) * bevel, -hh + bevel - sinf(a) * bevel, cosf(a), -sinf(a)]) }
        prof.append([R - bevel, -hh, 0, -1]); prof.append([0, -hh, 0, -1])

        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = []
        for q in prof {
            for s in 0...seg {
                let a = Float(s) / Float(seg) * .pi * 2, c = cosf(a), sn = sinf(a)
                verts.append(SCNVector3(q.x * c, q.y, q.x * sn))
                let n = simd_normalize(SIMD3(q.z * c, q.w, q.z * sn))
                norms.append(SCNVector3(n.x, n.y, n.z))
                uvs.append(CGPoint(x: CGFloat(q.x * c / R * 0.5 + 0.5), y: CGFloat(q.x * sn / R * 0.5 + 0.5)))
            }
        }
        var top: [Int32] = [], bot: [Int32] = []
        for p in 0..<(prof.count - 1) {
            let midY = (prof[p].y + prof[p + 1].y) * 0.5
            for s in 0..<seg {
                let i0 = Int32(p * (seg + 1) + s), i1 = i0 + Int32(seg + 1)
                let tris: [Int32] = [i0, i0 + 1, i1, i0 + 1, i1 + 1, i1]
                if midY < 0 { bot += tris } else { top += tris }
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: top, primitiveType: .triangles), SCNGeometryElement(indices: bot, primitiveType: .triangles)])
        return g
    }
}

// 駒のずれを毎回同じにするための小さな乱数
struct SeededRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 11) & ((1 << 53) - 1)) / Double(1 << 53)
    }
}

// 駒をラシャに置く「コトッ」と、裏返しの「カチッ」（Unity 版と同じ合成音）
final class Sfx {
    private var placePlayers: [AVAudioPlayer] = []
    private var flipPlayers: [AVAudioPlayer] = []
    private var pi = 0, fi = 0

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        placePlayers = Sfx.load("place.wav", count: 3)
        flipPlayers = Sfx.load("flip.wav", count: 8)
    }
    private static func load(_ name: String, count: Int) -> [AVAudioPlayer] {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return [] }
        return (0..<count).compactMap { _ in
            let p = try? AVAudioPlayer(contentsOf: url); p?.enableRate = true; p?.prepareToPlay(); return p
        }
    }
    func place() { play(placePlayers, &pi, vol: 0.75, rate: Float.random(in: 0.94...1.06)) }
    func flip() { play(flipPlayers, &fi, vol: 0.4, rate: Float.random(in: 0.9...1.1)) }
    private func play(_ ps: [AVAudioPlayer], _ i: inout Int, vol: Float, rate: Float) {
        guard !ps.isEmpty else { return }
        let p = ps[i % ps.count]; i += 1
        p.currentTime = 0; p.volume = vol; p.rate = rate; p.play()
    }
}
