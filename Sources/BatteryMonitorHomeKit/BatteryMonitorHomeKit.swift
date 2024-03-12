#if os(Linux)
import Glibc
import BluetoothLinux
#elseif os(macOS)
import Darwin
import DarwinGATT
#endif

import Foundation
import CoreFoundation
import Dispatch

import Bluetooth
import GATT
import HAP
import ArgumentParser

#if os(Linux)
typealias LinuxCentral = GATTCentral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
typealias LinuxPeripheral = GATTPeripheral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
typealias NativeCentral = LinuxCentral
typealias NativePeripheral = LinuxPeripheral
#elseif os(macOS)
typealias NativeCentral = DarwinCentral
typealias NativePeripheral = DarwinPeripheral
#else
#error("Unsupported platform")
#endif

@main
struct BatteryMonitorHomeKitTool: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        abstract: "A deamon for exposing Bluetooth battery monitors to HomeKit",
        version: "1.0.0"
    )
    
    @Option(help: "The name of the configuration file.")
    var file: String = "configuration.json"
    
    @Option(help: "The HomeKit setup code.")
    var setupCode: String?
    
    @Option(help: "The port of the HAP server.")
    var port: UInt = 8000
    
    @Option(help: "The scan duration.")
    var scanDuration: UInt = 45
    
    #if os(Linux)
    @Option(help: "Battery path.")
    var battery: String?
    #endif
    
    private static var controller: BridgeController!
    
    func run() throws {
        
        let batterySource: BatterySource?
        #if os(macOS)
        batterySource = MacBattery()
        #elseif os(Linux)
        batterySource = try self.battery.flatMap { try LinuxBattery(filePath: $0) }
        #endif
        
        let scanDuration = TimeInterval(self.scanDuration)
        
        // start async code
        Task {
            do {
                try await MainActor.run {
                    let controller = try BridgeController(
                        fileName: file,
                        setupCode: setupCode.map { .override($0) } ?? .random,
                        port: port, 
                        scanDuration: scanDuration,
                        battery: batterySource
                    )
                    controller.log = { print($0) }
                    controller.printPairingInstructions()
                    Self.controller = controller
                }
                try await Self.controller.scan(duration: scanDuration)
            }
            catch {
                fatalError("\(error)")
            }
        }
        
        // run main loop
        RunLoop.main.run()
    }
}
