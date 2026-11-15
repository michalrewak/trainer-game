using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Storage.Streams;

namespace BLEBridge;

/// <summary>
/// Main entry point — scans for BLE FTMS devices, connects, subscribes
/// to Indoor Bike Data characteristic and streams parsed frames via UDP.
/// </summary>
public static class Program
{
    // FTMS Service UUID
    private static readonly Guid FtmsServiceUuid =
        new("00001826-0000-1000-8000-00805f9b34fb");

    // Indoor Bike Data Characteristic UUID
    private static readonly Guid IndoorBikeDataUuid =
        new("00002ad2-0000-1000-8000-00805f9b34fb");

    private static UDPSender? _sender;
    private static bool _connected;

    public static async Task Main(string[] args)
    {
        int port = 7878;
        if (args.Length > 0 && int.TryParse(args[0], out int customPort))
            port = customPort;

        _sender = new UDPSender(port);

        Console.WriteLine($"[BLEBridge] Starting — UDP target: localhost:{port}");
        Console.WriteLine("[BLEBridge] Scanning for FTMS devices...");

        // Find BLE devices advertising FTMS service
        string selector = GattDeviceService.GetDeviceSelectorFromUuid(FtmsServiceUuid);
        var watcher = DeviceInformation.CreateWatcher(selector);

        watcher.Added += OnDeviceFound;
        watcher.EnumerationCompleted += (_, _) =>
        {
            if (!_connected)
                Console.WriteLine("[BLEBridge] Scan complete. Waiting for FTMS device to appear...");
        };
        watcher.Start();

        Console.WriteLine("[BLEBridge] Press Ctrl+C to exit.");
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = false;
            _sender?.Dispose();
            Console.WriteLine("[BLEBridge] Shutting down.");
        };

        // Keep alive
        await Task.Delay(Timeout.Infinite);
    }

    private static async void OnDeviceFound(DeviceWatcher watcher, DeviceInformation info)
    {
        if (_connected) return;
        _connected = true;

        Console.WriteLine($"[BLEBridge] Found device: {info.Name} ({info.Id})");

        try
        {
            using var service = await GattDeviceService.FromIdAsync(info.Id);
            if (service == null)
            {
                Console.WriteLine("[BLEBridge] Could not connect to FTMS service.");
                _connected = false;
                return;
            }

            var characteristics = await service.GetCharacteristicsForUuidAsync(IndoorBikeDataUuid);
            if (characteristics.Status != GattCommunicationStatus.Success ||
                characteristics.Characteristics.Count == 0)
            {
                Console.WriteLine("[BLEBridge] Indoor Bike Data characteristic not found.");
                _connected = false;
                return;
            }

            var characteristic = characteristics.Characteristics[0];

            // Subscribe to notifications
            var status = await characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.Notify);

            if (status != GattCommunicationStatus.Success)
            {
                Console.WriteLine($"[BLEBridge] Failed to subscribe: {status}");
                _connected = false;
                return;
            }

            Console.WriteLine("[BLEBridge] Connected and subscribed to Indoor Bike Data!");

            characteristic.ValueChanged += OnBikeDataReceived;

            // Keep connection alive
            await Task.Delay(Timeout.Infinite);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[BLEBridge] Error: {ex.Message}");
            _connected = false;
        }
    }

    private static void OnBikeDataReceived(
        GattCharacteristic sender,
        GattValueChangedEventArgs args)
    {
        var reader = DataReader.FromBuffer(args.CharacteristicValue);
        byte[] data = new byte[reader.UnconsumedBufferLength];
        reader.ReadBytes(data);

        var frame = FTMSParser.Parse(data);

        Console.WriteLine(
            $"  Power: {frame.InstantaneousPowerWatts,5:F0}W | " +
            $"Cadence: {frame.InstantaneousCadenceRpm,5:F0} RPM | " +
            $"Speed: {frame.InstantaneousSpeedKmh,5:F1} km/h");

        _sender?.Send(frame);
    }
}
