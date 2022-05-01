//
//  SettingsPluginsController.swift
//  XIV on Mac
//
//  Created by Chris Backas on 4/30/22.
//

import Cocoa

class SettingsPluginsController: NSViewController {

    @IBOutlet private var dalamud: NSButton!
    @IBOutlet private var delay: NSTextField!
    
    @IBOutlet weak var discord: NSButton!

    func updateView() {
        discord.state = DiscordBridge.enabled ? NSControl.StateValue.on : NSControl.StateValue.off
        
        dalamud.state = Dalamud.enabled ? NSControl.StateValue.on : NSControl.StateValue.off
        delay.stringValue = "\(Dalamud.delay)"
    }
    
    func saveState() {
        DispatchQueue.main.async { [self] in
            DiscordBridge.enabled = discord.state == NSControl.StateValue.on
            
            Dalamud.enabled = dalamud.state == NSControl.StateValue.on
            Dalamud.delay = Double(delay.stringValue) ?? Dalamud.defaultInjectionDelay
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
