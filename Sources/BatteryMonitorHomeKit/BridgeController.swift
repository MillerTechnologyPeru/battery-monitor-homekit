//
//  Controller.swift
//  
//
//  Created by Alsey Coleman Miller on 3/11/24.
//

import Foundation
import Bluetooth
import GATT
import HAP

#if os(Linux)
import Glibc
import BluetoothLinux
#elseif os(macOS)
import Darwin
import DarwinGATT
#endif

@MainActor
final class BridgeController {
    
    // MARK: - Properties
    
    var log: ((String) -> ())?
        
    private let hapDevice: HAP.Device
    
    private let server: HAP.Server
        
    private let battery: BatterySource?
    
    private let scanDuration: TimeInterval
    
    let configuration: BridgeConfiguration
        
    private var accessories = [NativeCentral.Peripheral: HAP.Accessory]()
    
    private var scanResults = [NativeCentral.Peripheral: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>]()
    
    // MARK: - Initialization
    
    public init(
        fileName: String,
        setupCode: HAP.Device.SetupCode,
        port: UInt,
        scanDuration: TimeInterval,
        battery: BatterySource? = nil
    ) throws {
        // start server
        let storage = ConfigurationHAPStorage(filename: fileName)
        let configuration: BridgeConfiguration = (try? storage.readConfiguration()).flatMap({ .init($0) }) ?? BridgeConfiguration()
        let info = Service.Info(
            name: configuration.name,
            serialNumber: configuration.serialNumber,
            model: configuration.model,
            firmwareRevision: BatteryMonitorHomeKitTool.configuration.version
        )
        var services = [HAP.Service]()
        if let battery = battery {
            services.append(BridgeBatteryService(source: battery))
        }
        let hapDevice = HAP.Device(
            bridgeInfo: info,
            setupCode: setupCode,
            storage: storage,
            services: services
        )
        self.hapDevice = hapDevice
        self.configuration = configuration
        self.battery = battery
        self.scanDuration = scanDuration
        self.server = try HAP.Server(device: hapDevice, listenPort: Int(port))
        self.hapDevice.delegate = self
    }
    
    // MARK: - Methods
    
    func scan(duration: TimeInterval) async throws {
        self.scanResults.removeAll(keepingCapacity: true)
        let scanTask = Task {
            let central = try await loadBluetooth()
            #if os(Linux)
            let stream = try await central.scan(
                filterDuplicates: false,
                parameters: HCILESetScanParameters(
                    type: .active,
                    interval:  .max,
                    window: .max,
                    addressType: .public,
                    filterPolicy: .accept
                )
            )
            #else
            let stream = try await central.scan(
                filterDuplicates: false
            )
            #endif
            Task {
                try await Task.sleep(timeInterval: 45)
                stream.stop()
            }
            for try await scanData in stream {
                await found(scanData)
            }
        }
        try await scanTask.value
        // create accessories
        for cache in scanResults.values {
            if try await bridge(BT20Accessory.self, from: cache) {
                continue
            } else {
                continue
            }
        }
        
        log?("Bridging \(accessories.count) accessories")
    }
    
    private func loadBluetooth(_ index: UInt = 0) async throws -> NativeCentral {
        
        #if os(Linux)
        var controllers = await HostController.controllers
        // keep trying to load Bluetooth device
        while controllers.isEmpty || controllers.count < index {
            log?("No Bluetooth adapters found")
            try await Task.sleep(timeInterval: 5.0)
            controllers = await HostController.controllers
        }
        var hostController: HostController = controllers[Int(index)]
        let address = try await hostController.readDeviceAddress()
        log?("Bluetooth Address: \(address)")
        let clientOptions = GATTCentralOptions(
            maximumTransmissionUnit: .max
        )
        let central = LinuxCentral(
            hostController: hostController,
            options: clientOptions,
            socket: BluetoothLinux.L2CAPSocket.self
        )
        #elseif os(macOS)
        let central = DarwinCentral()
        #else
        #error("Invalid platform")
        #endif
        
        #if DEBUG
        central.log = { print("Central: \($0)") }
        #endif
        
        #if os(macOS)
        // wait until XPC connection to blued is established and hardware is on
        try await central.waitPowerOn()
        #endif
        
        return central
    }
    
    private func found(_ scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>) async {
        // aggregate scan data
        assert(Thread.isMainThread)
        let oldCacheValue = scanResults[scanData.peripheral]
        // cache discovered peripheral in background
        let cache = await Task.detached {
            assert(Thread.isMainThread == false)
            var cache = oldCacheValue ?? ScanDataCache(scanData: scanData)
            cache += scanData
            #if canImport(CoreBluetooth)
            //cache.name = try? await central?.name(for: scanData.peripheral)
            for serviceUUID in scanData.advertisementData.overflowServiceUUIDs ?? [] {
                cache.overflowServiceUUIDs.insert(serviceUUID)
            }
            #endif
            return cache
        }.value
        scanResults[scanData.peripheral] = cache
        assert(Thread.isMainThread)
    }
    
    @discardableResult
    private func bridge<T>(
        _ accessoryType: T.Type,
        from scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>
    ) async throws -> Bool where T: BatteryMonitorAccessory, T: HAP.Accessory {
        guard let advertisement = T.Advertisement.init(scanData: scanData) else {
            return false
        }
        let peripheral = scanData.scanData.peripheral
        guard filter(scanData) else {
            log?("Ignoring \(T.accessoryType) \(peripheral.description)")
            return false
        }
        if let _ = self.accessories[scanData.scanData.peripheral] as? T {
            return true
        } else {
            let central = try await loadBluetooth()
            let newAccessory = T.init(
                peripheral: peripheral,
                central: central,
                advertisement: advertisement,
                configuration: configuration(for: scanData)
            )
            self.accessories[peripheral] = newAccessory
            self.hapDevice.addAccessories([newAccessory])
            log?("Found \(T.Advertisement.accessoryType) \(peripheral.description)")
            return true
        }
    }
    
    private func filter(_ scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) -> Bool {
        // filtering disabled
        guard configuration.accessories.isEmpty == false else {
            return true
        }
        return configuration(for: scanData) != nil
    }
    
    private func configuration(for scanData: ScanDataCache<NativeCentral.Peripheral, NativeCentral.Advertisement>) -> BridgeConfiguration.Accessory? {
        return configuration.accessories
            .first(where: { $0.id == scanData.scanData.peripheral.description || $0.id == scanData.localName })
    }
}

// MARK: - HAP Device Delegate

extension BridgeController: HAP.DeviceDelegate {
    
    func didRequestIdentificationOf(_ accessory: Accessory) {
        log?("Requested identification of accessory \(String(describing: accessory.info.name.value ?? ""))")
    }

    func characteristic<T>(_ characteristic: HAP.GenericCharacteristic<T>,
                           ofService service: HAP.Service,
                           ofAccessory accessory: HAP.Accessory,
                           didChangeValue newValue: T?) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") did change: \(String(describing: newValue))")
        
    }

    func characteristicListenerDidSubscribe(_ accessory: HAP.Accessory,
                                            service: HAP.Service,
                                            characteristic: AnyCharacteristic) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") got a subscriber")
    }

    func characteristicListenerDidUnsubscribe(_ accessory: HAP.Accessory,
                                              service: HAP.Service,
                                              characteristic: AnyCharacteristic) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") lost a subscriber")
    }
    
    func didChangePairingState(from: PairingState, to: PairingState) {
        if to == .notPaired {
            printPairingInstructions()
        }
    }
    
    func printPairingInstructions() {
        if hapDevice.isPaired {
            log?("The device is paired, either unpair using your iPhone or remove the configuration file.")
        } else {
            log?("Scan the following QR code using your iPhone to pair this device:")
            log?(hapDevice.setupQRCode.asText)
        }
    }
}

internal extension HAP.Device {
    
    /// A bridge is a special type of HAP accessory server that bridges HomeKit
    /// Accessory Protocol and different RF/transport protocols, such as ZigBee
    /// or Z-Wave. A bridge must expose all the user-addressable functionality
    /// supported by its connected devices as HAP accessory objects to the HAP
    /// controller(s). A bridge must ensure that the instance ID assigned to the
    /// HAP accessory objects exposed on behalf of its connected devices do not
    /// change for the lifetime of the server/client pairing.
    ///
    /// For example, a bridge that bridges three lights would expose four HAP
    /// accessory objects: one HAP accessory object that represents the bridge
    /// itself that may include a "firmware update" service, and three
    /// additional HAP accessory objects that each contain a "lightbulb"
    /// service.
    ///
    /// A bridge must not expose more than 100 HAP accessory objects.
    ///
    /// Any accessories, regardless of transport, that enable physical access to
    /// the home, such as door locks, must not be bridged. Accessories that
    /// support IP transports, such as Wi-Fi, must not be bridged. Accessories
    /// that support Bluetooth LE that can be controlled, such as a light bulb,
    /// must not be bridged. Accessories that support Bluetooth LE that only
    /// provide data, such as a temperature sensor, and accessories that support
    /// other transports, such as a ZigBee light bulb or a proprietary RF
    /// sensor, may be bridged.
    ///
    /// - Parameters:
    ///   - bridgeInfo: information about the bridge
    ///   - setupCode: the code to pair this device, must be in the format XXX-XX-XXX
    ///   - storage: persistence interface for storing pairings, secrets
    ///   - accessories: accessories to be bridged
    convenience init(
        bridgeInfo: HAP.Service.Info,
        setupCode: SetupCode = .random,
        storage: Storage,
        services: [HAP.Service]
    ) {
        let bridge = Accessory(info: bridgeInfo, type: .bridge, services: services)
        self.init(setupCode: setupCode, storage: storage, accessory: bridge)
    }
}
