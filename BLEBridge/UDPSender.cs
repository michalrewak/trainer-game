using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace BLEBridge;

/// <summary>
/// Sends TrainerFrame data to the Unity game via UDP on localhost.
/// </summary>
public sealed class UDPSender : IDisposable
{
    private readonly UdpClient _client;
    private readonly IPEndPoint _endpoint;

    public UDPSender(int port = 7878)
    {
        _client = new UdpClient();
        _endpoint = new IPEndPoint(IPAddress.Loopback, port);
    }

    public void Send(TrainerFrame frame)
    {
        var json = JsonSerializer.Serialize(new
        {
            power = Math.Round(frame.InstantaneousPowerWatts, 1),
            cadence = Math.Round(frame.InstantaneousCadenceRpm, 1),
            speed = Math.Round(frame.InstantaneousSpeedKmh, 1),
            timestamp = frame.TimestampMs
        });

        byte[] bytes = Encoding.UTF8.GetBytes(json);
        _client.Send(bytes, bytes.Length, _endpoint);
    }

    public void Dispose()
    {
        _client.Dispose();
    }
}
