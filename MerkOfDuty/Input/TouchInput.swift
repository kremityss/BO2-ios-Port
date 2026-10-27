import UIKit
import MetalKit
import simd

/// Left thumb floating movement stick. A short/full-forward throw controls
/// walk/run/auto-tactical-sprint without a separate oversized sprint button.
final class MovePad: UIView {
    var onVector: ((SIMD2<Float>) -> Void)?
    private let ring = UIView()
    private let thumb = UIView()
    private var anchor: CGPoint?
    private weak var ownedTouch: UITouch?
    private let maxRange: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        ring.backgroundColor = UIColor.black.withAlphaComponent(0.17)
        ring.layer.borderWidth = 1.5
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        ring.layer.cornerRadius = 53
        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.29)
        thumb.layer.cornerRadius = 21
        thumb.layer.borderWidth = 1.5
        thumb.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
        addSubview(ring)
        addSubview(thumb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = CGRect(x:center.x-53,y:center.y-53,width:106,height:106)
        thumb.bounds = CGRect(x:0,y:0,width:42,height:42)
        if ownedTouch == nil {thumb.center=center}
    }
    private func move(_ touch: UITouch) {
        guard let anchor else {return}
        let p = touch.location(in:self)
        let dx=p.x-anchor.x, dy=p.y-anchor.y
        let length=max(1,hypot(dx,dy)), amount=min(maxRange,length)
        let sx=dx/length*amount, sy=dy/length*amount
        thumb.center=CGPoint(x:anchor.x+sx,y:anchor.y+sy)
        let vector=SIMD2<Float>(Float(sx/maxRange),Float(-sy/maxRange))
        onVector?(vector)
        // Visible white rim at full-forward throw makes auto-sprint discoverable.
        ring.layer.borderColor = (vector.y > 0.80 && simd_length(vector) > 0.86
            ? UIColor.systemOrange : UIColor.white.withAlphaComponent(0.42)).cgColor
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard ownedTouch == nil,let t=touches.first else{return}
        ownedTouch=t
        anchor=t.location(in:self)
        setNeedsLayout()
        move(t)
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        if let t=ownedTouch,touches.contains(t){move(t)}
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){release(touches)}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){release(touches)}
    private func release(_ touches:Set<UITouch>) {
        guard let t=ownedTouch,touches.contains(t) else{return}
        ownedTouch=nil
        anchor=nil
        ring.layer.borderColor=UIColor.white.withAlphaComponent(0.42).cgColor
        onVector?(.zero)
        setNeedsLayout()
    }
}

/// Clear swiping area under the right-hand HUD; action buttons capture their
/// own touches, so ADS/fire and camera look work simultaneously.
final class LookPad:UIView {
    var onLook:((Float,Float)->Void)?
    private weak var activeTouch:UITouch?
    private var last:CGPoint?
    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?){
        guard activeTouch == nil,let touch=touches.first else{return}
        activeTouch=touch
        last=touch.location(in:self)
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?){
        guard let t=activeTouch,touches.contains(t),let last else{return}
        let now=t.location(in:self)
        onLook?(Float(now.x-last.x),Float(now.y-last.y))
        self.last=now
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){reset(touches)}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){reset(touches)}
    private func reset(_ touches:Set<UITouch>){
        guard let t=activeTouch,touches.contains(t) else{return}
        activeTouch=nil
        last=nil
    }
}

/// Lightweight native radar: bots are dots relative to player, rotated with
/// heading. It does not copy CODM interface images or require a WebView.
final class TacticalRadar:UIView {
    weak var world:GameWorld?
    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor=UIColor(red:0.015,green:0.032,blue:0.044,alpha:0.66)
        layer.cornerRadius=10
        layer.borderWidth=1
        layer.borderColor=UIColor.white.withAlphaComponent(0.30).cgColor
        isOpaque=false
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func draw(_ rect:CGRect){
        guard let context=UIGraphicsGetCurrentContext(),let world else{return}
        let mid=CGPoint(x:bounds.midX,y:bounds.midY)
        let r=min(bounds.width,bounds.height)*0.43
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.17).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in:CGRect(x:mid.x-r,y:mid.y-r,width:r*2,height:r*2))
        context.move(to:CGPoint(x:mid.x,y:mid.y-r));context.addLine(to:CGPoint(x:mid.x,y:mid.y+r))
        context.move(to:CGPoint(x:mid.x-r,y:mid.y));context.addLine(to:CGPoint(x:mid.x+r,y:mid.y))
        context.strokePath()
        for bot in world.bots where bot.alive {
            let dx=bot.position.x-world.pos.x, dz=bot.position.z-world.pos.z
            // Player view forward stays at radar top.
            let side=dx*cos(world.yaw)+dz*sin(world.yaw)
            let front=dx*sin(world.yaw)-dz*cos(world.yaw)
            let x=mid.x+CGFloat(side/32)*r,y=mid.y-CGFloat(front/32)*r
            if hypot(x-mid.x,y-mid.y)<r {
                context.setFillColor(UIColor.systemRed.cgColor)
                context.fillEllipse(in:CGRect(x:x-2.5,y:y-2.5,width:5,height:5))
            }
        }
        context.setFillColor(UIColor.white.cgColor)
        let arrow=UIBezierPath()
        arrow.move(to:CGPoint(x:mid.x,y:mid.y-7))
        arrow.addLine(to:CGPoint(x:mid.x-5,y:mid.y+5))
        arrow.addLine(to:CGPoint(x:mid.x+5,y:mid.y+5))
        arrow.close()
        context.addPath(arrow.cgPath)
        context.fillPath()
    }
}

final class FPSViewController:UIViewController {
    private var renderer:GameRenderer!
    private let screen=MTKView(frame:.zero)
    private let look=LookPad(frame:.zero)
    private let move=MovePad(frame:.zero)
    private let radar=TacticalRadar(frame:.zero)
    private let stats=UILabel()
    private let ammo=UILabel()
    private let mapName=UILabel()
    private let performance=UILabel()
    private let reticle=UILabel()
    private let healthBackground=UIView()
    private let healthFill=UIView()
    private var fire:UIButton!
    private var ads:UIButton!
    private var jump:UIButton!
    private var slide:UIButton!
    private var reload:UIButton!
    private var swap:UIButton!
    private var respawn:UIButton!
    private var hudReady=false

    override var prefersStatusBarHidden:Bool {true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask {.landscape}
    override var shouldAutorotate:Bool {true}

    override func viewDidLoad(){
        super.viewDidLoad()
        view.backgroundColor = .black
        screen.frame=view.bounds
        // Render at a measured mobile resolution rather than forcing 3x
        // Retina resolution; this cuts fill-rate on high-density iPhones.
        screen.contentScaleFactor=min(UIScreen.main.scale, 2.0)
        screen.autoresizingMask=[.flexibleWidth,.flexibleHeight]
        view.addSubview(screen)
        guard let r=GameRenderer(view:screen) else {
            let error=UILabel(frame:view.bounds)
            error.text="Metal graphics are not available"
            error.textColor = .white
            error.textAlignment = .center
            view.addSubview(error)
            return
        }
        renderer=r
        configureHUD()
        configureControls()
        hudReady=true
        renderer.onHUD = { [weak self] _ in
            // The MTKView can render on a non-main thread on some devices.
            if Thread.isMainThread {self?.updateHUD()}
            else {DispatchQueue.main.async {self?.updateHUD()}}
        }
        updateHUD()
    }

    private func configureHUD(){
        func label(_ label:UILabel,size:CGFloat,weight:UIFont.Weight = .semibold) {
            label.font = .monospacedSystemFont(ofSize:size,weight:weight)
            label.textColor = .white
            label.shadowColor = .black
            label.shadowOffset = CGSize(width:0,height:1)
            label.adjustsFontSizeToFitWidth=true
            label.minimumScaleFactor=0.7
            view.addSubview(label)
        }
        radar.world=renderer.world
        view.addSubview(radar)
        label(mapName,size:9,weight:.heavy)
        mapName.text="NUKETOWN // TDM TEST"
        label(stats,size:11,weight:.heavy)
        stats.textAlignment = .center
        label(ammo,size:15,weight:.heavy)
        ammo.textAlignment = .center
        ammo.backgroundColor=UIColor.black.withAlphaComponent(0.38)
        ammo.layer.cornerRadius=8
        ammo.clipsToBounds=true
        label(performance,size:10)
        performance.textAlignment = .right
        label(reticle,size:26,weight:.light)
        reticle.text="+"
        reticle.textAlignment = .center
        healthBackground.backgroundColor=UIColor.black.withAlphaComponent(0.45)
        healthBackground.layer.cornerRadius=3
        healthFill.backgroundColor=UIColor.systemGreen
        healthFill.layer.cornerRadius=2
        view.addSubview(healthBackground)
        healthBackground.addSubview(healthFill)
    }

    private func makeAction(_ title:String,symbol:String,accent:Bool=false) -> UIButton {
        let b=UIButton(type:.system)
        var configuration=UIButton.Configuration.plain()
        configuration.image=UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(pointSize:18,weight:.semibold))
        configuration.title=title
        configuration.imagePlacement = .top
        configuration.imagePadding = 1
        configuration.baseForegroundColor = accent ? UIColor(red:1,green:0.65,blue:0.26,alpha:1) : .white
        configuration.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { attributes in
            var a=attributes
            a.font=UIFont.systemFont(ofSize:9,weight:.bold)
            return a
        }
        b.configuration=configuration
        b.layer.cornerRadius=27
        b.layer.borderWidth=1.15
        b.layer.borderColor=(accent ? UIColor.systemOrange : UIColor.white).withAlphaComponent(0.55).cgColor
        b.backgroundColor=UIColor.black.withAlphaComponent(0.31)
        b.isExclusiveTouch=false
        return b
    }

    private func configureControls(){
        view.addSubview(look)
        look.onLook={ [weak self] dx,dy in self?.renderer.world.aim(dx:dx,dy:dy) }
        view.addSubview(move)
        move.onVector={ [weak self] vector in
            guard let world=self?.renderer.world else {return}
            world.controls.move=vector
            world.controls.sprint=vector.y>0.80 && simd_length(vector)>0.86
        }
        fire=makeAction("FIRE",symbol:"scope",accent:true)
        ads=makeAction("ADS",symbol:"viewfinder")
        jump=makeAction("JUMP",symbol:"arrow.up")
        slide=makeAction("SLIDE",symbol:"figure.run")
        reload=makeAction("RELOAD",symbol:"arrow.clockwise")
        swap=makeAction("SWAP",symbol:"arrow.left.arrow.right")
        respawn=makeAction("RESET",symbol:"arrow.counterclockwise")
        for b in [fire!,ads!,jump!,slide!,reload!,swap!,respawn!] {view.addSubview(b)}
        fire.addTarget(self,action:#selector(fireDown),for:.touchDown)
        fire.addTarget(self,action:#selector(fireUp),for:[.touchUpInside,.touchUpOutside,.touchCancel])
        // CODM-style tap-to-ADS, not a hold-only action.
        ads.addTarget(self,action:#selector(toggleADS),for:.touchDown)
        jump.addTarget(self,action:#selector(queueJump),for:.touchDown)
        slide.addTarget(self,action:#selector(queueSlideOrCrouch),for:.touchDown)
        reload.addTarget(self,action:#selector(queueReload),for:.touchDown)
        swap.addTarget(self,action:#selector(queueSwap),for:.touchDown)
        respawn.addTarget(self,action:#selector(resetSpawn),for:.touchDown)
    }

    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews()
        guard hudReady else{return}
        let w=view.bounds.width, h=view.bounds.height
        let safe=view.safeAreaInsets
        let right=w-safe.right, left=safe.left, top=safe.top
        let s=min(1, h/390)
        radar.frame=CGRect(x:left+12,y:top+10,width:86*s,height:86*s)
        mapName.frame=CGRect(x:left+13,y:top+99*s,width:148*s,height:14*s)
        stats.frame=CGRect(x:w/2-115*s,y:top+12,width:230*s,height:28*s)
        performance.frame=CGRect(x:right-112*s,y:top+10,width:70*s,height:22*s)
        respawn.frame=CGRect(x:right-40*s,y:top+8,width:36*s,height:36*s)
        respawn.layer.cornerRadius=18*s
        healthBackground.frame=CGRect(x:left+12,y:top+118*s,width:110*s,height:7*s)
        healthFill.frame=CGRect(x:1,y:1,width:108*s,height:5*s)
        reticle.frame=CGRect(x:w/2-13*s,y:h/2-13*s,width:26*s,height:26*s)
        ammo.frame=CGRect(x:right-245*s,y:h-safe.bottom-41*s,width:108*s,height:29*s)
        look.frame=CGRect(x:w*0.38,y:0,width:w*0.62,height:h)
        move.frame=CGRect(x:left+4,y:h*0.53,width:w*0.31,height:h*0.43)
        func place(_ button:UIButton,_ x:CGFloat,_ y:CGFloat,_ diameter:CGFloat){
            let d=diameter*s
            button.frame=CGRect(x:x-d/2,y:y-d/2,width:d,height:d)
            button.layer.cornerRadius=d/2
        }
        // Responsive, thumb-reachable right action cluster; clear gaps keep
        // independent multitouch look input available between buttons.
        place(fire,right-62*s,h*0.56,72)
        place(jump,right-54*s,h*0.32,54)
        place(ads,right-158*s,h*0.51,55)
        place(slide,right-125*s,h*0.81,54)
        place(reload,right-215*s,h*0.80,48)
        place(swap,right-245*s,h*0.48,45)
    }

    private func updateHUD(){
        guard let renderer else{return}
        let world=renderer.world
        stats.text="K \(world.kills)   D \(world.deaths)   •   \(Int(world.health)) HP"
        ammo.text="\(world.weapon.name)  \(world.ammo)/\(world.reserveAmmo)"
        performance.text="\(renderer.measuredFPS) FPS"
        let factor=min(1,view.bounds.height/390)
        healthFill.frame=CGRect(x:1,y:1,width:108*factor*min(1,CGFloat(world.health)/100),height:5*factor)
        healthFill.backgroundColor=world.health<35 ? .systemRed : .systemGreen
        reticle.textColor=world.recentHit>0 ? .systemRed : .white
        radar.setNeedsDisplay()
        ads.layer.borderColor=(world.controls.ads ? UIColor.systemOrange : UIColor.white.withAlphaComponent(0.55)).cgColor
        if var config=slide.configuration {
            config.title=world.controls.crouch ? "STAND" : "SLIDE"
            slide.configuration=config
        }
        if world.health<=0 {mapName.text="RESPAWNING // NUKETOWN"}
        else {mapName.text="NUKETOWN // TDM TEST"}
    }

    @objc private func fireDown(){renderer.world.controls.firing=true}
    @objc private func fireUp(){renderer.world.controls.firing=false}
    @objc private func toggleADS(){renderer.world.controls.ads.toggle()}
    @objc private func queueJump(){
        let w=renderer.world
        w.controls.crouch=false
        w.controls.jumpQueued=true
    }
    @objc private func queueSlideOrCrouch(){
        let w=renderer.world
        if simd_length(w.controls.move) > 0.50 && w.isGrounded {
            w.controls.crouch=false
            w.controls.slideQueued=true
        } else {
            w.controls.crouch.toggle()
        }
    }
    @objc private func queueReload(){renderer.world.controls.reloadQueued=true}
    @objc private func queueSwap(){renderer.world.switchWeapon()}
    @objc private func resetSpawn(){renderer.world.debugRespawn()}
}
