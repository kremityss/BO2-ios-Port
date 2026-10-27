import UIKit
import MetalKit
import simd

final class MovePad: UIView {
    var onVector: ((SIMD2<Float>) -> Void)?
    private let ring = UIView()
    private let thumb = UIView()
    private var anchor: CGPoint?
    private weak var ownedTouch: UITouch?
    private let maxRange: CGFloat = 51

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        ring.layer.borderWidth = 1
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        ring.layer.cornerRadius = 74
        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.24)
        thumb.layer.cornerRadius = 27
        thumb.layer.borderWidth = 1
        thumb.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        addSubview(ring)
        addSubview(thumb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = CGRect(x: center.x - 74, y: center.y - 74, width: 148, height: 148)
        if ownedTouch == nil { thumb.center = center }
        thumb.bounds = CGRect(x: 0,y: 0,width: 54,height: 54)
    }
    private func move(_ touch: UITouch) {
        guard let anchor else { return }
        let current = touch.location(in: self)
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        let mag = max(1, sqrt(dx*dx + dy*dy))
        let factor = min(maxRange,mag) / mag
        thumb.center = CGPoint(x: anchor.x + dx*factor, y: anchor.y + dy*factor)
        onVector?(SIMD2<Float>(Float(dx*factor/maxRange), Float(-dy*factor/maxRange)))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ownedTouch == nil, let touch = touches.first else { return }
        ownedTouch = touch
        anchor = touch.location(in: self)
        setNeedsLayout()
        move(touch)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let ownedTouch, touches.contains(ownedTouch) { move(ownedTouch) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    private func end(_ touches: Set<UITouch>) {
        guard let ownedTouch, touches.contains(ownedTouch) else { return }
        self.ownedTouch = nil
        anchor = nil
        onVector?(.zero)
        setNeedsLayout()
    }
}

final class LookPad: UIView {
    var onLook: ((Float, Float) -> Void)?
    private weak var activeTouch: UITouch?
    private var lastPoint: CGPoint?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        lastPoint = touch.location(in: self)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch), let lastPoint else { return }
        let point = activeTouch.location(in: self)
        onLook?(Float(point.x-lastPoint.x), Float(point.y-lastPoint.y))
        self.lastPoint = point
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { reset(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset(touches) }
    private func reset(_ touches: Set<UITouch>) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
        lastPoint = nil
    }
}

final class FPSViewController: UIViewController {
    private var renderer: GameRenderer!
    private let screen = MTKView(frame: .zero)
    private let look = LookPad(frame: .zero)
    private let move = MovePad(frame: .zero)
    private let hud = UILabel()
    private let reticle = UILabel()
    private let info = UILabel()
    private let buttons = UIStackView()
    private var fire: UIButton!
    private var ads: UIButton!
    private var sprint: UIButton!
    private var crouch: UIButton!

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        screen.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen)
        NSLayoutConstraint.activate([
            screen.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.topAnchor.constraint(equalTo: view.topAnchor),
            screen.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        guard let r = GameRenderer(view: screen) else {
            let failure = UILabel(frame: view.bounds)
            failure.text = "Metal-capable iPhone required"
            failure.textAlignment = .center
            failure.textColor = .white
            view.addSubview(failure)
            return
        }
        renderer = r
        setupHUD()
        setupControls()
        renderer.onHUD = { [weak self] text in
            self?.hud.text = text
            if let world = self?.renderer.world { self?.reticle.textColor = world.recentHit > 0 ? .systemRed : .white }
        }
    }

    private func setupHUD() {
        hud.numberOfLines = 2
        hud.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        hud.textColor = .white
        hud.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        hud.layer.cornerRadius = 7
        hud.layer.masksToBounds = true
        hud.text = "M27   30/240    100 HP"
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)
        reticle.text = "+"
        reticle.font = UIFont.monospacedSystemFont(ofSize: 23, weight: .light)
        reticle.textColor = .white
        reticle.textAlignment = .center
        reticle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle)
        info.text = "MERK OF DUTY  /  NATIVE METAL  /  TRAINING"
        info.textColor = UIColor.white.withAlphaComponent(0.75)
        info.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        info.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(info)
        NSLayoutConstraint.activate([
            hud.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15),
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hud.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 40),
            reticle.heightAnchor.constraint(equalToConstant: 40),
            info.topAnchor.constraint(equalTo: hud.bottomAnchor, constant: 6),
            info.leadingAnchor.constraint(equalTo: hud.leadingAnchor)
        ])
    }

    private func setupControls() {
        let world = renderer.world
        // Look area deliberately excludes the action buttons. Multi-touch works
        // because the joystick/look pad track independent UITouch objects.
        look.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(look)
        look.onLook = { [weak self] dx,dy in self?.renderer.world.aim(dx: dx, dy: dy) }
        NSLayoutConstraint.activate([
            look.leadingAnchor.constraint(equalTo: view.centerXAnchor),
            look.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            look.topAnchor.constraint(equalTo: view.topAnchor),
            look.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        move.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(move)
        move.onVector = { [weak self] vector in self?.renderer.world.controls.move = vector }
        NSLayoutConstraint.activate([
            move.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            move.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -3),
            move.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.37),
            move.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.56)
        ])
        fire = makeButton("FIRE", tint: .systemOrange)
        ads = makeButton("ADS")
        sprint = makeButton("SPRINT")
        crouch = makeButton("SLIDE")
        let jump = makeButton("JUMP")
        let reload = makeButton("RELOAD")
        let swap = makeButton("SWAP")
        for b in [fire!,ads!,sprint!,crouch!,jump,reload,swap] { view.addSubview(b) }
        func place(_ b: UIButton, right: CGFloat, bottom: CGFloat, size: CGFloat = 59) {
            NSLayoutConstraint.activate([
                b.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -right),
                b.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -bottom),
                b.widthAnchor.constraint(equalToConstant: size),
                b.heightAnchor.constraint(equalToConstant: size)
            ])
        }
        place(fire, right: 22, bottom: 67, size: 76)
        place(ads, right: 119, bottom: 68)
        place(jump, right: 48, bottom: 155)
        place(crouch, right: 190, bottom: 10)
        place(sprint, right: 266, bottom: 10)
        place(reload, right: 122, bottom: 3, size: 51)
        place(swap, right: 192, bottom: 100, size: 49)
        fire.addTarget(self, action: #selector(fireDown), for: .touchDown)
        fire.addTarget(self, action: #selector(fireUp), for: [.touchUpInside,.touchUpOutside,.touchCancel])
        ads.addTarget(self, action: #selector(adsDown), for: .touchDown)
        ads.addTarget(self, action: #selector(adsUp), for: [.touchUpInside,.touchUpOutside,.touchCancel])
        sprint.addTarget(self, action: #selector(sprintDown), for: .touchDown)
        sprint.addTarget(self, action: #selector(sprintUp), for: [.touchUpInside,.touchUpOutside,.touchCancel])
        jump.addAction(UIAction { [weak self] _ in self?.renderer.world.controls.jumpQueued = true }, for: .touchDown)
        crouch.addAction(UIAction { [weak self] _ in self?.renderer.world.controls.slideQueued = true }, for: .touchDown)
        reload.addAction(UIAction { [weak self] _ in self?.renderer.world.controls.reloadQueued = true }, for: .touchDown)
        swap.addAction(UIAction { [weak self] _ in self?.renderer.world.switchWeapon() }, for: .touchDown)
        _ = world
    }

    private func makeButton(_ text: String, tint: UIColor = .white) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 10, weight: .heavy)
        b.setTitleColor(tint, for: .normal)
        b.layer.cornerRadius = 12
        b.layer.borderWidth = 1
        b.layer.borderColor = tint.withAlphaComponent(0.5).cgColor
        b.backgroundColor = UIColor.black.withAlphaComponent(0.44)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isExclusiveTouch = false
        return b
    }

    @objc private func fireDown() { renderer.world.controls.firing = true }
    @objc private func fireUp() { renderer.world.controls.firing = false }
    @objc private func adsDown() { renderer.world.controls.ads = true }
    @objc private func adsUp() { renderer.world.controls.ads = false }
    @objc private func sprintDown() { renderer.world.controls.sprint = true }
    @objc private func sprintUp() { renderer.world.controls.sprint = false }
}
