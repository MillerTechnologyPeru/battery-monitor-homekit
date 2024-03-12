//
//  TB6000Pro.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Topdon
/*
final class TB6000ProAccessory: HAP.Accessory.Switch, BatteryMonitorAccessory {
    
    static var accessoryType: BatteryMonitorAccessoryType { .tb6000Pro }
    
    
}
*/
// MARK: - BatteryMonitorAdvertisement

extension Topdon.TB6000Pro: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .bt20 }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        self.init(scanData)
    }
}
