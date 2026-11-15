using DesertSurvival.Progression;
using DesertSurvival.Trainer;
using DesertSurvival.Vehicle;
using DesertSurvival.World;
using UnityEngine;

namespace DesertSurvival.Session
{
    /// <summary>
    /// Manages the expedition gameplay loop:
    /// Start at base → drive out → collect resources → return to base → upgrade.
    /// </summary>
    public class ExpeditionManager : MonoBehaviour
    {
        [Header("References")]
        [SerializeField] private TrainerInputManager trainerInput;
        [SerializeField] private VehicleController vehicle;
        [SerializeField] private EnergySystem energySystem;
        [SerializeField] private InventoryManager inventory;
        [SerializeField] private UpgradeManager upgradeManager;
        [SerializeField] private SaveManager saveManager;
        [SerializeField] private POIManager poiManager;
        [SerializeField] private FogOfWar fogOfWar;
        [SerializeField] private HazardSystem hazardSystem;

        [Header("Base")]
        [SerializeField] private Transform basePosition;
        [SerializeField] private float baseReturnRadius = 15f;

        [Header("Session")]
        [SerializeField] private float sessionTimeLimit = 1200f; // 20 min default

        public ExpeditionState State { get; private set; } = ExpeditionState.AtBase;
        public float SessionTimer { get; private set; }
        public float PedalTimeThisSession { get; private set; }
        public float DistanceFromBase { get; private set; }

        public bool IsAtBase =>
            basePosition != null &&
            Vector3.Distance(vehicle.transform.position, basePosition.position) <= baseReturnRadius;

        private void Start()
        {
            saveManager.Load();
            upgradeManager.ApplyUpgrades();
            hazardSystem.CoolingMultiplier = upgradeManager.GetCoolingMultiplier();
            energySystem.Refill();
            State = ExpeditionState.AtBase;
        }

        private void Update()
        {
            if (basePosition != null)
                DistanceFromBase = Vector3.Distance(vehicle.transform.position, basePosition.position);

            switch (State)
            {
                case ExpeditionState.AtBase:
                    UpdateAtBase();
                    break;
                case ExpeditionState.Exploring:
                    UpdateExploring();
                    break;
                case ExpeditionState.Returning:
                    UpdateReturning();
                    break;
            }
        }

        private void UpdateAtBase()
        {
            // Player is at base — can do upgrades via UI
            // Start expedition when player begins pedaling and moves away
            if (!IsAtBase && trainerInput.Current.power > 10f)
            {
                State = ExpeditionState.Exploring;
                SessionTimer = 0f;
                PedalTimeThisSession = 0f;
            }
        }

        private void UpdateExploring()
        {
            float dt = Time.deltaTime;
            SessionTimer += dt;

            if (trainerInput.Current.power > 5f)
                PedalTimeThisSession += dt;

            // Update world systems
            poiManager.UpdateDiscovery(vehicle.transform.position);
            fogOfWar.RevealAt(vehicle.transform.position);
            hazardSystem.ProcessPower(trainerInput.Current.power, dt);

            // Check if player returned to base
            if (IsAtBase && SessionTimer > 5f)
            {
                CompleteExpedition();
            }

            // Emergency: out of energy and not pedaling
            if (energySystem.IsEmpty && trainerInput.Current.power < 5f)
            {
                State = ExpeditionState.Returning;
            }
        }

        private void UpdateReturning()
        {
            float dt = Time.deltaTime;
            SessionTimer += dt;

            if (trainerInput.Current.power > 5f)
                PedalTimeThisSession += dt;

            // Still update systems — player can still pedal back
            fogOfWar.RevealAt(vehicle.transform.position);
            hazardSystem.ProcessPower(trainerInput.Current.power, dt);

            if (IsAtBase)
                CompleteExpedition();

            // If player resumes pedaling and recharges, go back to exploring
            if (!energySystem.IsEmpty && trainerInput.Current.power > 50f)
                State = ExpeditionState.Exploring;
        }

        private void CompleteExpedition()
        {
            State = ExpeditionState.AtBase;
            energySystem.Refill();
            hazardSystem.CoolingMultiplier = upgradeManager.GetCoolingMultiplier();

            saveManager.RecordSession(PedalTimeThisSession);
            saveManager.Save();

            Debug.Log($"[Expedition] Session complete! " +
                      $"Time: {SessionTimer:F0}s, " +
                      $"Pedal time: {PedalTimeThisSession:F0}s, " +
                      $"Total sessions: {saveManager.TotalSessions}");
        }

        /// <summary>Called by UI when player purchases an upgrade at base.</summary>
        public void OnUpgradePurchased()
        {
            upgradeManager.ApplyUpgrades();
            hazardSystem.CoolingMultiplier = upgradeManager.GetCoolingMultiplier();
            saveManager.Save();
        }
    }

    public enum ExpeditionState
    {
        AtBase,
        Exploring,
        Returning
    }
}
