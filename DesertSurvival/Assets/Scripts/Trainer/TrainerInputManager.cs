using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using UnityEngine;

namespace DesertSurvival.Trainer
{
    /// <summary>
    /// Receives trainer data from BLEBridge via UDP and provides smoothed values.
    /// Falls back to keyboard simulation when no trainer is connected.
    /// </summary>
    public class TrainerInputManager : MonoBehaviour
    {
        [Header("Network")]
        [SerializeField] private int udpPort = 7878;

        [Header("Smoothing")]
        [SerializeField] private float smoothingWindow = 0.5f;

        [Header("Keyboard Fallback")]
        [SerializeField] private float simulatedPower = 150f;
        [SerializeField] private float simulatedCadence = 80f;

        /// <summary>Current smoothed trainer data.</summary>
        public TrainerData Current { get; private set; }

        /// <summary>True when receiving data from a real trainer.</summary>
        public bool IsTrainerConnected { get; private set; }

        private UdpClient _udpClient;
        private Thread _receiveThread;
        private volatile bool _running;

        private TrainerData _rawLatest;
        private TrainerData _smoothed;
        private float _lastReceiveTime;

        private void OnEnable()
        {
            _running = true;
            _udpClient = new UdpClient(udpPort);
            _receiveThread = new Thread(ReceiveLoop)
            {
                IsBackground = true,
                Name = "TrainerUDP"
            };
            _receiveThread.Start();
        }

        private void OnDisable()
        {
            _running = false;
            _udpClient?.Close();
            _receiveThread?.Join(500);
        }

        private void Update()
        {
            float timeSinceData = Time.time - _lastReceiveTime;
            IsTrainerConnected = timeSinceData < 3f;

            if (IsTrainerConnected)
            {
                // Exponential moving average smoothing
                float alpha = 1f - Mathf.Exp(-Time.deltaTime / smoothingWindow);
                _smoothed.power = Mathf.Lerp(_smoothed.power, _rawLatest.power, alpha);
                _smoothed.cadence = Mathf.Lerp(_smoothed.cadence, _rawLatest.cadence, alpha);
                _smoothed.speed = Mathf.Lerp(_smoothed.speed, _rawLatest.speed, alpha);
                _smoothed.timestamp = _rawLatest.timestamp;
            }
            else
            {
                // Keyboard fallback: Up arrow = pedaling
                bool pedaling = Input.GetKey(KeyCode.UpArrow) || Input.GetKey(KeyCode.W);
                float targetPower = pedaling ? simulatedPower : 0f;
                float targetCadence = pedaling ? simulatedCadence : 0f;

                float alpha = 1f - Mathf.Exp(-Time.deltaTime / 0.3f);
                _smoothed.power = Mathf.Lerp(_smoothed.power, targetPower, alpha);
                _smoothed.cadence = Mathf.Lerp(_smoothed.cadence, targetCadence, alpha);
                _smoothed.speed = 0f;
            }

            Current = _smoothed;
        }

        private void ReceiveLoop()
        {
            IPEndPoint remote = new(IPAddress.Any, 0);

            while (_running)
            {
                try
                {
                    byte[] bytes = _udpClient.Receive(ref remote);
                    string json = Encoding.UTF8.GetString(bytes);
                    _rawLatest = JsonUtility.FromJson<TrainerData>(json);
                    _lastReceiveTime = Time.time;
                }
                catch (ObjectDisposedException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    if (_running)
                        Debug.LogWarning($"[TrainerInput] UDP error: {ex.Message}");
                }
            }
        }
    }
}
