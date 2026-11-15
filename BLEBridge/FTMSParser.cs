namespace BLEBridge;

/// <summary>
/// Parsed FTMS Indoor Bike Data (characteristic UUID 0x2AD2).
/// </summary>
public readonly struct TrainerFrame
{
    public double InstantaneousPowerWatts { get; init; }
    public double InstantaneousCadenceRpm { get; init; }
    public double InstantaneousSpeedKmh { get; init; }
    public long TimestampMs { get; init; }
}

/// <summary>
/// Parses the FTMS Indoor Bike Data characteristic per Bluetooth FTMS spec section 4.9.
/// The first 2 bytes are flags indicating which optional fields are present.
/// </summary>
public static class FTMSParser
{
    public static TrainerFrame Parse(byte[] data)
    {
        if (data.Length < 2)
            return default;

        ushort flags = BitConverter.ToUInt16(data, 0);
        int offset = 2;

        double speedKmh = 0;
        double cadenceRpm = 0;
        double powerWatts = 0;

        // Bit 0: More Data — if 0 instantaneous speed is present (uint16, 0.01 km/h resolution)
        if ((flags & 0x0001) == 0)
        {
            if (offset + 2 <= data.Length)
            {
                ushort rawSpeed = BitConverter.ToUInt16(data, offset);
                speedKmh = rawSpeed * 0.01;
            }
            offset += 2;
        }

        // Bit 1: Average Speed present (uint16, 0.01 km/h) — skip
        if ((flags & 0x0002) != 0)
            offset += 2;

        // Bit 2: Instantaneous Cadence present (uint16, 0.5 RPM resolution)
        if ((flags & 0x0004) != 0)
        {
            if (offset + 2 <= data.Length)
            {
                ushort rawCadence = BitConverter.ToUInt16(data, offset);
                cadenceRpm = rawCadence * 0.5;
            }
            offset += 2;
        }

        // Bit 3: Average Cadence (uint16, 0.5 RPM) — skip
        if ((flags & 0x0008) != 0)
            offset += 2;

        // Bit 4: Total Distance (uint24) — skip
        if ((flags & 0x0010) != 0)
            offset += 3;

        // Bit 5: Resistance Level (sint16) — skip
        if ((flags & 0x0020) != 0)
            offset += 2;

        // Bit 6: Instantaneous Power (sint16, 1 Watt resolution)
        if ((flags & 0x0040) != 0)
        {
            if (offset + 2 <= data.Length)
            {
                short rawPower = BitConverter.ToInt16(data, offset);
                powerWatts = Math.Max(0, rawPower);
            }
            offset += 2;
        }

        // Remaining fields (average power, expended energy, heart rate, etc.) — ignored for POC

        return new TrainerFrame
        {
            InstantaneousPowerWatts = powerWatts,
            InstantaneousCadenceRpm = cadenceRpm,
            InstantaneousSpeedKmh = speedKmh,
            TimestampMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        };
    }
}
