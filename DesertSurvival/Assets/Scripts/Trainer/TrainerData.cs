using System;

namespace DesertSurvival.Trainer
{
    /// <summary>
    /// Data received from the bike trainer via BLEBridge UDP stream.
    /// </summary>
    [Serializable]
    public struct TrainerData
    {
        public float power;    // Watts
        public float cadence;  // RPM
        public float speed;    // km/h
        public long timestamp; // Unix ms
    }
}
