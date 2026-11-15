using UnityEngine;

namespace DesertSurvival.Vehicle
{
    /// <summary>
    /// Manages the vehicle's energy/battery system.
    /// Pedaling charges the battery; driving and systems consume it.
    /// </summary>
    public class EnergySystem : MonoBehaviour
    {
        [Header("Capacity")]
        [SerializeField] private float maxEnergy = 100f;
        [SerializeField] private float currentEnergy = 100f;

        [Header("Charge")]
        [Tooltip("Energy gained per watt of power per second")]
        [SerializeField] private float chargeRatePerWatt = 0.01f;

        [Header("Drain")]
        [Tooltip("Base energy drain per second while moving")]
        [SerializeField] private float baseDrainRate = 1f;

        /// <summary>Current energy level (0 to MaxEnergy).</summary>
        public float CurrentEnergy => currentEnergy;
        public float MaxEnergy => maxEnergy;
        public float EnergyPercent => maxEnergy > 0 ? currentEnergy / maxEnergy : 0f;
        public bool IsEmpty => currentEnergy <= 0f;

        // Upgrade multipliers — set by UpgradeManager
        public float CapacityMultiplier { get; set; } = 1f;
        public float EfficiencyMultiplier { get; set; } = 1f;

        public float EffectiveMaxEnergy => maxEnergy * CapacityMultiplier;

        /// <summary>Charge the battery based on trainer power output.</summary>
        public void Charge(float powerWatts, float deltaTime)
        {
            float gain = powerWatts * chargeRatePerWatt * EfficiencyMultiplier * deltaTime;
            currentEnergy = Mathf.Min(currentEnergy + gain, EffectiveMaxEnergy);
        }

        /// <summary>Drain energy. Returns actual amount drained.</summary>
        public float Drain(float amount)
        {
            float drained = Mathf.Min(amount, currentEnergy);
            currentEnergy -= drained;
            return drained;
        }

        /// <summary>Drain the base movement cost for this frame.</summary>
        public void DrainMovement(float speedFactor, float deltaTime)
        {
            float cost = baseDrainRate * speedFactor * deltaTime;
            Drain(cost);
        }

        public void Refill()
        {
            currentEnergy = EffectiveMaxEnergy;
        }
    }
}
