//
//  BM2.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Leagend



// MARK: - BatteryMonitorAdvertisement

extension Leagend.BM2.Advertisement: BatteryMonitorAdvertisement {
    
    static public var accessoryType: BatteryMonitorAccessoryType { .bm2 }
    
    init?(scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        self.init(scanData)
    }
}
