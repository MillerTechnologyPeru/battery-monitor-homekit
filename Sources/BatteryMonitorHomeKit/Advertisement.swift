//
//  Advertisement.swift
//  
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT

/// Battery Monitor Advertisement protocol
protocol BatteryMonitorAdvertisement {
    
    static var accessoryType: BatteryMonitorAccessoryType { get }

    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>)
}
