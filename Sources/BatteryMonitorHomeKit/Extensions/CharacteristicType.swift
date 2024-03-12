//
//  CharacteristicType.swift
//
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import HAP

public extension CharacteristicType {
    
    static var eveVoltage: CharacteristicType {
        .custom(UUID(uuidString: "E863F10A-079E-48FF-8F27-9C2605A29F52")!)
    }
    
    static var eveCurrent: CharacteristicType {
        .custom(UUID(uuidString: "E863F126-079E-48FF-8F27-9C2605A29F52")!)
    }
    
    static var eveConsumption: CharacteristicType {
        .custom(UUID(uuidString: "E863F10D-079E-48FF-8F27-9C2605A29F52")!)
    }
}
