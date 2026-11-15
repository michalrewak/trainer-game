using DesertSurvival.Vehicle;
using UnityEngine;

namespace DesertSurvival.Session
{
    /// <summary>
    /// Desert hazards: sandstorms and overheating.
    /// Drains extra energy and reduces visibility.
    /// </summary>
    public class HazardSystem : MonoBehaviour
    {
        [Header("Sandstorm")]
        [SerializeField] private float stormChancePerMinute = 0.15f;
        [SerializeField] private float stormDurationMin = 20f;
        [SerializeField] private float stormDurationMax = 45f;
        [SerializeField] private float stormEnergyDrainPerSec = 2f;

        [Header("Overheat")]
        [Tooltip("Power threshold above which overheat builds up")]
        [SerializeField] private float overheatPowerThreshold = 250f;
        [SerializeField] private float overheatBuildRate = 0.1f;
        [SerializeField] private float overheatDecayRate = 0.05f;
        [SerializeField] private float overheatEnergyDrainPerSec = 1.5f;

        [Header("References")]
        [SerializeField] private EnergySystem energySystem;

        /// <summary>True when a sandstorm is active.</summary>
        public bool IsStormActive { get; private set; }

        /// <summary>How overheated the vehicle is (0-1).</summary>
        public float OverheatLevel { get; private set; }

        /// <summary>Set by UpgradeManager — reduces hazard damage.</summary>
        public float CoolingMultiplier { get; set; } = 1f;

        public float StormTimeRemaining { get; private set; }

        private float _stormCheckTimer;

        private void Update()
        {
            float dt = Time.deltaTime;

            UpdateStorm(dt);
            UpdateOverheat(dt);
        }

        private void UpdateStorm(float dt)
        {
            if (IsStormActive)
            {
                StormTimeRemaining -= dt;
                if (StormTimeRemaining <= 0f)
                {
                    IsStormActive = false;
                    StormTimeRemaining = 0f;
                    return;
                }

                // Storm drains energy, reduced by cooling upgrade
                float drain = stormEnergyDrainPerSec / CoolingMultiplier * dt;
                energySystem.Drain(drain);
            }
            else
            {
                _stormCheckTimer += dt;
                if (_stormCheckTimer >= 60f)
                {
                    _stormCheckTimer = 0f;
                    if (Random.value < stormChancePerMinute)
                    {
                        IsStormActive = true;
                        StormTimeRemaining = Random.Range(stormDurationMin, stormDurationMax);
                    }
                }
            }
        }

        public void UpdateOverheat(float dt)
        {
            // Overheat is driven externally — call with current power
        }

        /// <summary>Call each frame with current power to update overheat.</summary>
        public void ProcessPower(float currentPowerWatts, float dt)
        {
            if (currentPowerWatts > overheatPowerThreshold)
            {
                float excess = (currentPowerWatts - overheatPowerThreshold) / overheatPowerThreshold;
                OverheatLevel = Mathf.Min(1f, OverheatLevel + excess * overheatBuildRate * dt / CoolingMultiplier);
            }
            else
            {
                OverheatLevel = Mathf.Max(0f, OverheatLevel - overheatDecayRate * dt);
            }

            if (OverheatLevel > 0.5f)
            {
                float drain = overheatEnergyDrainPerSec * OverheatLevel / CoolingMultiplier * dt;
                energySystem.Drain(drain);
            }
        }
    }
}
