using DesertSurvival.Trainer;
using UnityEngine;

namespace DesertSurvival.Vehicle
{
    /// <summary>
    /// Controls the desert vehicle. Pedaling provides thrust; keyboard/pad steers.
    /// Power from the trainer maps to forward force; cadence affects efficiency.
    /// </summary>
    [RequireComponent(typeof(EnergySystem))]
    [RequireComponent(typeof(Rigidbody))]
    public class VehicleController : MonoBehaviour
    {
        [Header("References")]
        [SerializeField] private TrainerInputManager trainerInput;

        [Header("Movement")]
        [SerializeField] private float baseForceFactor = 5f;
        [SerializeField] private float referencePowerWatts = 150f;
        [SerializeField] private float maxSpeedKmh = 60f;
        [SerializeField] private float brakeDrag = 5f;
        [SerializeField] private float normalDrag = 0.5f;

        [Header("Steering")]
        [SerializeField] private float turnSpeed = 90f;

        [Header("Cadence Efficiency")]
        [SerializeField] private float optimalCadenceLow = 70f;
        [SerializeField] private float optimalCadenceHigh = 90f;
        [SerializeField] private float efficiencyDropoff = 0.5f;

        [Header("Sprint")]
        [SerializeField] private float sprintThresholdMultiplier = 1.5f;
        [SerializeField] private float sprintBoost = 1.5f;
        [SerializeField] private float averagePowerWindow = 30f;

        // Upgrade multipliers — set by UpgradeManager
        public float DriveMultiplier { get; set; } = 1f;
        public float TractionMultiplier { get; set; } = 1f;

        /// <summary>Current speed in km/h (for HUD).</summary>
        public float CurrentSpeedKmh => _rb.velocity.magnitude * 3.6f;

        /// <summary>Whether a sprint boost is active.</summary>
        public bool IsSprinting { get; private set; }

        private Rigidbody _rb;
        private EnergySystem _energy;
        private float _averagePower;

        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
            _energy = GetComponent<EnergySystem>();
        }

        private void FixedUpdate()
        {
            if (trainerInput == null) return;

            var data = trainerInput.Current;

            // Update rolling average power for sprint detection
            float alpha = 1f - Mathf.Exp(-Time.fixedDeltaTime / averagePowerWindow);
            _averagePower = Mathf.Lerp(_averagePower, data.power, alpha);

            // Sprint detection
            IsSprinting = _averagePower > 10f && data.power > _averagePower * sprintThresholdMultiplier;

            // Cadence efficiency curve
            float efficiency = CalculateCadenceEfficiency(data.cadence);

            // Charge battery from pedaling
            _energy.Charge(data.power, Time.fixedDeltaTime);

            // If no energy, vehicle cannot move
            if (_energy.IsEmpty && data.power < 10f)
            {
                _rb.drag = brakeDrag;
                return;
            }

            _rb.drag = normalDrag;

            // Forward force proportional to power
            float powerRatio = data.power / referencePowerWatts;
            float force = baseForceFactor * powerRatio * efficiency * DriveMultiplier;
            if (IsSprinting) force *= sprintBoost;

            // Clamp speed
            if (CurrentSpeedKmh < maxSpeedKmh)
            {
                _rb.AddForce(transform.forward * force, ForceMode.Force);
            }

            // Drain energy for movement
            float speedFactor = Mathf.Clamp01(CurrentSpeedKmh / maxSpeedKmh);
            _energy.DrainMovement(speedFactor, Time.fixedDeltaTime);

            // Steering
            float steerInput = Input.GetAxis("Horizontal");
            float turnAmount = steerInput * turnSpeed * TractionMultiplier * Time.fixedDeltaTime;
            Quaternion turnRotation = Quaternion.Euler(0f, turnAmount, 0f);
            _rb.MoveRotation(_rb.rotation * turnRotation);
        }

        private float CalculateCadenceEfficiency(float cadence)
        {
            if (cadence < 1f) return 0f;

            if (cadence >= optimalCadenceLow && cadence <= optimalCadenceHigh)
                return 1f;

            float distance;
            if (cadence < optimalCadenceLow)
                distance = (optimalCadenceLow - cadence) / optimalCadenceLow;
            else
                distance = (cadence - optimalCadenceHigh) / optimalCadenceHigh;

            return Mathf.Max(efficiencyDropoff, 1f - distance);
        }
    }
}
