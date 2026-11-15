using DesertSurvival.Progression;
using DesertSurvival.Session;
using DesertSurvival.Trainer;
using DesertSurvival.Vehicle;
using UnityEngine;
using UnityEngine.UI;

namespace DesertSurvival.UI
{
    /// <summary>
    /// In-game HUD — large, high-contrast Fallout/Pipboy style.
    /// Designed to be readable from ~1m away while sweating on a trainer.
    /// </summary>
    public class HUDController : MonoBehaviour
    {
        [Header("References")]
        [SerializeField] private TrainerInputManager trainerInput;
        [SerializeField] private VehicleController vehicle;
        [SerializeField] private EnergySystem energySystem;
        [SerializeField] private InventoryManager inventory;
        [SerializeField] private ExpeditionManager expedition;
        [SerializeField] private HazardSystem hazardSystem;

        [Header("UI Elements — Top Bar (Trainer Data)")]
        [SerializeField] private Text powerText;
        [SerializeField] private Text cadenceText;
        [SerializeField] private Text connectionIndicator;

        [Header("UI Elements — Center")]
        [SerializeField] private Text speedText;
        [SerializeField] private Slider energyBar;
        [SerializeField] private Text energyPercent;

        [Header("UI Elements — Bottom")]
        [SerializeField] private Text cargoText;
        [SerializeField] private Text sessionTimerText;
        [SerializeField] private Text distanceText;

        [Header("UI Elements — Warnings")]
        [SerializeField] private GameObject stormWarning;
        [SerializeField] private GameObject overheatWarning;
        [SerializeField] private GameObject lowEnergyWarning;
        [SerializeField] private GameObject sprintIndicator;

        [Header("UI Elements — State")]
        [SerializeField] private Text expeditionStateText;

        private void Update()
        {
            UpdateTrainerDisplay();
            UpdateVehicleDisplay();
            UpdateExpeditionDisplay();
            UpdateWarnings();
        }

        private void UpdateTrainerDisplay()
        {
            if (trainerInput == null) return;

            var data = trainerInput.Current;
            if (powerText != null)
                powerText.text = $"{data.power:F0} W";
            if (cadenceText != null)
                cadenceText.text = $"{data.cadence:F0} RPM";
            if (connectionIndicator != null)
                connectionIndicator.text = trainerInput.IsTrainerConnected ? "TRAINER" : "KEYBOARD";
        }

        private void UpdateVehicleDisplay()
        {
            if (vehicle != null && speedText != null)
                speedText.text = $"{vehicle.CurrentSpeedKmh:F0} km/h";

            if (energySystem != null)
            {
                if (energyBar != null)
                    energyBar.value = energySystem.EnergyPercent;
                if (energyPercent != null)
                    energyPercent.text = $"{energySystem.EnergyPercent * 100f:F0}%";
            }

            if (inventory != null && cargoText != null)
                cargoText.text = $"CARGO: {inventory.UsedCargo}/{inventory.MaxCargo}";
        }

        private void UpdateExpeditionDisplay()
        {
            if (expedition == null) return;

            if (sessionTimerText != null)
            {
                int minutes = Mathf.FloorToInt(expedition.SessionTimer / 60f);
                int seconds = Mathf.FloorToInt(expedition.SessionTimer % 60f);
                sessionTimerText.text = $"{minutes:D2}:{seconds:D2}";
            }

            if (distanceText != null)
                distanceText.text = $"{expedition.DistanceFromBase:F0}m";

            if (expeditionStateText != null)
            {
                expeditionStateText.text = expedition.State switch
                {
                    ExpeditionState.AtBase => ">> BAZA <<",
                    ExpeditionState.Exploring => "WYPRAWA",
                    ExpeditionState.Returning => "!! POWROT !!",
                    _ => ""
                };
            }
        }

        private void UpdateWarnings()
        {
            if (stormWarning != null)
                stormWarning.SetActive(hazardSystem != null && hazardSystem.IsStormActive);

            if (overheatWarning != null)
                overheatWarning.SetActive(hazardSystem != null && hazardSystem.OverheatLevel > 0.5f);

            if (lowEnergyWarning != null)
                lowEnergyWarning.SetActive(energySystem != null && energySystem.EnergyPercent < 0.2f);

            if (sprintIndicator != null)
                sprintIndicator.SetActive(vehicle != null && vehicle.IsSprinting);
        }
    }
}
