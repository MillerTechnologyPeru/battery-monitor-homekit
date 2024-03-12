//
//  Accessory.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT

/// Battery Monitor Accessory
protocol BatteryMonitorAccessory: AnyObject {
    
    associatedtype Advertisement: BatteryMonitorAdvertisement
        
    var peripheral: NativeCentral.Peripheral { get }
    
    var central: NativeCentral { get }
    
    var advertisement: Advertisement { get }
    
    init(
        peripheral: NativeCentral.Peripheral,
        central: NativeCentral,
        advertisement: Advertisement,
        configuration: BridgeConfiguration.Accessory?
    )
}

extension BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { Advertisement.accessoryType }
}

/// Battery Monitor Accessory Type
public enum BatteryMonitorAccessoryType: String, Codable, Sendable, CaseIterable {
    
    case bt20 = "BT20"
    case tb6000Pro = "TB6000Pro"
    case bm2 = "BM2"
    case powerWatchdog = "PowerWatchdog"
}
