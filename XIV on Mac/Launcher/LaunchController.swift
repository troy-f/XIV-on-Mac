//
//  LaunchController.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 02.02.22.
//

import Cocoa

class LaunchController: NSViewController {
    var loginSheetWinController: NSWindowController?
    var installerWinController: NSWindowController?
    var patchWinController: NSWindowController?
    var repairWinController: NSWindowController?
    var firstAidWinController: NSWindowController?
    var patchController: PatchController?
    var repairController: RepairController?
    var newsTable: FrontierTableView!
    var topicsTable: FrontierTableView!
    var otp: OTP?
    
    @IBOutlet private var loginButton: NSButton!
    @IBOutlet var userField: NSTextField!
    @IBOutlet private var userMenu: NSMenu!
    @IBOutlet private var passwdField: NSTextField!
    @IBOutlet var otpField: NSTextField!
    @IBOutlet var otpCheck: NSButton!
    @IBOutlet var autoLoginCheck: NSButton!
    @IBOutlet private var scrollView: AnimatingScrollView!
    @IBOutlet private var newsView: NSScrollView!
    @IBOutlet private var topicsView: NSScrollView!
    @IBOutlet var discloseButton: NSButton!
    @IBOutlet private var touchBarLoginButton: NSButtonTouchBarItem!
    
    override func loadView() {
        super.loadView()
        update()
        NotificationCenter.default.addObserver(self, selector: #selector(installDone(_:)), name: .installDone, object: nil)
        userMenu.minimumWidth = 264
        newsTable = FrontierTableView(icon: NSImage(systemSymbolName: "newspaper", accessibilityDescription: nil)!)
        topicsTable = FrontierTableView(icon: NSImage(systemSymbolName: "newspaper.fill", accessibilityDescription: nil)!)
        newsView.documentView = newsTable.tableView
        topicsView.documentView = topicsTable.tableView
        DispatchQueue.global(qos: .userInitiated).async {
            self.checkBoot()
        }
        DispatchQueue.global(qos: .userInteractive).async {
            if let frontier = Frontier.info {
                self.populateNews(frontier)
            }
        }
    }
    
    @objc func installDone(_ notif: Notification) {
        checkBoot()
    }
    
    func checkBoot() {
        if let bootPatches = try? Patch.bootPatches, !bootPatches.isEmpty, FFXIVApp().installed {
            startPatch(bootPatches)
        }
        DispatchQueue.main.async {
            self.loginButton.isEnabled = true
            self.touchBarLoginButton.isEnabled = true
            if settings.autoLogin && NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) != .shift {
                self.doLogin()
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        loginSheetWinController = storyboard?.instantiateController(withIdentifier: "LoginSheet") as? NSWindowController
        installerWinController = storyboard?.instantiateController(withIdentifier: "InstallerWindow") as? NSWindowController
        patchWinController = storyboard?.instantiateController(withIdentifier: "PatchSheet") as? NSWindowController
        repairWinController = storyboard?.instantiateController(withIdentifier: "RepairSheet") as? NSWindowController
        patchController = patchWinController!.contentViewController! as? PatchController
        repairController = repairWinController!.contentViewController! as? RepairController
        firstAidWinController = storyboard?.instantiateController(withIdentifier: "FirstAidWindow") as? NSWindowController
    }
    
    private func populateNews(_ info: Frontier.Info) {
        DispatchQueue.main.async {
            self.topicsTable.add(items: info.topics)
            self.newsTable.add(items: info.pinned + info.news)
            self.scrollView.banners = info.banner
        }
    }
    
    private func update() {
        autoLoginCheck.state = Settings.autoLogin ? .on : .off
        userField.stringValue = Settings.credentials?.username ?? ""
        passwdField.stringValue = Settings.credentials?.password ?? ""
        setupOTP()
    }
    
    @objc func update(_ sender: userMenuItem) {
        userField.stringValue = sender.credentials.username
        passwdField.stringValue = sender.credentials.password
        setupOTP()
    }
    
    @IBAction func showAccounts(_ sender: Any) {
        userMenu.items = []
        let accounts = LoginCredentials.accounts
        for account in accounts {
            let item = userMenuItem(title: account.username, action: #selector(update(_:)), keyEquivalent: "")
            item.credentials = account
            userMenu.items += [item]
        }
        userMenu.popUp(positioning: userMenu.item(at: 0), at: NSPoint(x: 0, y: 29), in: userField)
    }
    
    @IBAction func autoLoginStateChange(_ sender: NSButton) {
        Settings.autoLogin = sender.state == .on
        
        if Settings.autoLogin {
            let alert: NSAlert = .init()
            alert.messageText = NSLocalizedString("AUTOLOGIN_MESSAGE", comment: "")
            alert.informativeText = NSLocalizedString("AUTOLOGIN_INFORMATIVE", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
            
            alert.runModal()
        }
    }
    
    @IBAction func doLogin(_ sender: Any) {
        doLogin()
    }
    
    @IBAction func doRepair(_ sender: Any) {
        doLogin(repair: true)
    }
    
    func problemConfigurationCheck() -> Bool {
        let firstAidController = firstAidWinController!.contentViewController! as! FirstAidController
        if firstAidController.cfgCheckSevereProblems() {
            firstAidWinController!.window?.makeKeyAndOrderFront(self)
            return true
        }
        // If there were no major problems, see if we need to apply the Retina bug workaround.
        firstAidController.applyRetinaWorkaround()
        return false
    }
    
    func doLogin(repair: Bool = false) {
        // Check for show stopping problems
        if problemConfigurationCheck() {
            return
        }
        view.window?.beginSheet(loginSheetWinController!.window!)
        Settings.credentials = LoginCredentials(username: userField.stringValue, password: passwdField.stringValue, oneTimePassword: otpField.stringValue)
        DispatchQueue.global(qos: .default).async {
            do {
                guard FFXIVApp().installed else {
                    throw FFXIVLoginError.noInstall
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    DiscordBridge.setPresence()
                    Dxvk.install()
                }
                if Frontier.loginMaintenance {
                    throw FFXIVLoginError.maintenance
                }
                let loginResult = try LoginResult(repair)
                guard loginResult.state != .NoService else {
                    throw FFXIVLoginError.notPlayable
                }
                guard loginResult.state != .NoTerms else {
                    Wine.launch(command: "\"\(FFXIVApp().bootExe64URL.path)\"")
                    throw FFXIVLoginError.noTerms
                }
                if repair {
                    DispatchQueue.main.async { [self] in
                        loginSheetWinController?.window?.close()
                        view.window?.beginSheet(repairWinController!.window!)
                        repairController?.repair(loginResult)
                    }
                    return
                }
                if !(loginResult.pendingPatches?.isEmpty ?? true) {
                    DispatchQueue.main.async { [self] in
                        loginSheetWinController?.window?.close()
                    }
                    self.startPatch(loginResult.pendingPatches!)
                    DispatchQueue.main.async { [self] in
                        view.window?.beginSheet(loginSheetWinController!.window!)
                    }
                }
                if Frontier.gameMaintenance {
                    throw FFXIVLoginError.maintenance
                }
                NotificationCenter.default.post(name: .loginInfo, object: nil, userInfo: [Notification.status.info: "Updating Dalamud"])
                let dalamudInstallState = loginResult.dalamudInstallState
                DispatchQueue.main.async {
                    if Settings.dalamudEnabled && dalamudInstallState == .failed {
                        let alert = NSAlert()
                        alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                        alert.alertStyle = .critical
                        alert.messageText = NSLocalizedString("DALAMUD_START_FAILURE", comment: "")
                        alert.informativeText = NSLocalizedString("DALAMUD_START_FAILURE_INFORMATIONAL", comment: "")
                        alert.runModal()
                    }
                }
                NotificationCenter.default.post(name: .loginInfo, object: nil, userInfo: [Notification.status.info: "Starting Game"])
                let process = try loginResult.startGame(dalamudInstallState == .ok)
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    view.window?.close()
                }
                AddOn.launchNotify()
                let exitCode = process.exitCode
                Log.information("Game exited with exit code \(exitCode)")
                DispatchQueue.main.async {
                    if exitCode != 0 && Settings.nonZeroExitError {
                        let alert = NSAlert()
                        alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                        alert.alertStyle = .critical
                        alert.messageText = NSLocalizedString("GAME_START_FAILURE", comment: "")
                        alert.informativeText = NSLocalizedString("GAME_START_FAILURE_INFORMATIONAL", comment: "")
                        alert.runModal()
                    } else if Settings.exitWithGame {
                        Util.quit()
                    }
                }
            } catch FFXIVLoginError.noInstall {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    view.window?.beginSheet(self.installerWinController!.window!)
                }
            } catch let XLError.loginError(errorMessage) {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString("LOGIN_ERROR", comment: "")
                    alert.informativeText = errorMessage
                    alert.runModal()
                }
            } catch let XLError.startError(errorMessage) {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString("START_ERROR", comment: "")
                    alert.informativeText = errorMessage
                    alert.runModal()
                }
            } catch let error as FFXIVLoginError {
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = error.failureReason ?? "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            } catch { // should not reach
                DispatchQueue.main.async { [self] in
                    loginSheetWinController?.window?.close()
                    let alert = NSAlert()
                    alert.addButton(withTitle: NSLocalizedString("BUTTON_OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.messageText = "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
    
    func startPatch(_ patches: [Patch]) {
        if Thread.isMainThread {
            view.window?.beginSheet(patchWinController!.window!)
        } else {
            DispatchQueue.main.sync { [self] in
                view.window?.beginSheet(patchWinController!.window!)
            }
        }
        patchController?.install(patches)
    }
    
    @IBAction func tapTroubleshooting(_ sender: Any) {
        firstAidWinController?.showWindow(self)
    }
    
    @IBAction func tapACT(_ sender: Any) {
        ACT.launch()
    }
    
    @IBAction func tapIINACT(_ sender: Any) {
        IINACT.launch()
    }
    
    @IBAction func tapBunnyHUD(_ sender: Any) {
        BunnyHUD.launch()
    }
    
    @IBAction func tapAnamnesis(_ sender: Any) {
        Anamnesis.launch()
    }
}

class userMenuItem: NSMenuItem {
    var credentials: LoginCredentials!
}

final class BannerView: NSImageView {
    var banner: Frontier.Info.Banner? {
        didSet {
            self.image = Frontier.fetchImage(url: URL(string: banner!.lsbBanner)!)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let banner = banner {
            let url = URL(string: banner.link)!
            NSWorkspace.shared.open(url)
        }
    }
}

final class AnimatingScrollView: NSScrollView {
    private var width: CGFloat {
        return contentSize.width
    }
    
    private var height: CGFloat {
        return contentSize.height
    }
    
    private let animationDuration = 2.0
    private let stayDuration = 8.0
    private var index = 0
    private var timer = Timer()
    
    var banners: [Frontier.Info.Banner]? {
        didSet {
            let banners = banners!
            documentView?.setFrameSize(NSSize(width: width * CGFloat(banners.count), height: height))
            for (i, banner) in banners.enumerated() {
                let bannerView = BannerView()
                bannerView.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: height)
                bannerView.imageScaling = .scaleProportionallyUpOrDown
                bannerView.banner = banner
                documentView?.addSubview(bannerView)
            }
            startTimer()
        }
    }
    
    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: stayDuration, repeats: true, block: { _ in
            self.animate()
        })
    }
    
    func stopTimer() {
        timer.invalidate()
    }
    
    // This will override and cancel any running scroll animations
    override public func scroll(_ clipView: NSClipView, to point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.setBoundsOrigin(point)
        CATransaction.commit()
        super.scroll(clipView, to: point)
        index = Int(floor((point.x + width / 2) / width))
        let snap_x = CGFloat(index) * width
        scroll(toPoint: NSPoint(x: snap_x, y: 0), animationDuration: animationDuration)
        startTimer()
    }
    
    private func scroll(toPoint: NSPoint, animationDuration: Double) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = animationDuration
        contentView.animator().setBoundsOrigin(toPoint)
        reflectScrolledClipView(contentView)
        NSAnimationContext.endGrouping()
    }
    
    private func animate() {
        if let banners = banners {
            index = (index + 1) % banners.count
            scroll(toPoint: NSPoint(x: Int(width) * index, y: 0), animationDuration: animationDuration)
        }
    }
}
