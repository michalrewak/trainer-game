using System;
using System.Collections.Generic;
using DesertSurvival.Vehicle;
using DesertSurvival.World;
using UnityEngine;

namespace DesertSurvival.Progression
{
    /// <summary>
    /// Defines and manages vehicle upgrades.
    /// Each upgrade has 3 levels with increasing resource costs.
    /// </summary>
    public class UpgradeManager : MonoBehaviour
    {
        [Header("References")]
        [SerializeField] private EnergySystem energySystem;
        [SerializeField] private VehicleController vehicleController;
        [SerializeField] private POIManager poiManager;
        [SerializeField] private FogOfWar fogOfWar;
        [SerializeField] private InventoryManager inventory;

        public static readonly UpgradeDefinition[] Upgrades = new[]
        {
            new UpgradeDefinition
            {
                Id = "battery",
                Name = "Akumulator",
                Description = "Wieksza pojemnosc energii",
                MaxLevel = 3,
                BonusPerLevel = 0.3f, // +30% per level
                Costs = new[]
                {
                    Cost(3, 1, 0, 0),  // Level 1: 3 scrap, 1 electronics
                    Cost(6, 3, 0, 1),  // Level 2
                    Cost(10, 5, 2, 2)  // Level 3
                }
            },
            new UpgradeDefinition
            {
                Id = "drive",
                Name = "Naped",
                Description = "Lepsza konwersja mocy na predkosc",
                MaxLevel = 3,
                BonusPerLevel = 0.15f,
                Costs = new[]
                {
                    Cost(2, 2, 0, 0),
                    Cost(4, 4, 1, 0),
                    Cost(8, 6, 2, 1)
                }
            },
            new UpgradeDefinition
            {
                Id = "cooling",
                Name = "Chlodzenie",
                Description = "Mniejsze straty energii w burzy",
                MaxLevel = 3,
                BonusPerLevel = 0.25f,
                Costs = new[]
                {
                    Cost(2, 0, 1, 2),
                    Cost(4, 2, 2, 4),
                    Cost(6, 4, 3, 6)
                }
            },
            new UpgradeDefinition
            {
                Id = "radar",
                Name = "Radar",
                Description = "Wykrywanie zasobow z daleka",
                MaxLevel = 3,
                BonusPerLevel = 0.5f,
                Costs = new[]
                {
                    Cost(1, 3, 0, 0),
                    Cost(3, 5, 1, 0),
                    Cost(5, 8, 2, 1)
                }
            },
            new UpgradeDefinition
            {
                Id = "cargo",
                Name = "Ladownia",
                Description = "Wiecej miejsca na surowce",
                MaxLevel = 3,
                BonusPerLevel = 0.4f,
                Costs = new[]
                {
                    Cost(4, 0, 1, 0),
                    Cost(7, 2, 2, 1),
                    Cost(12, 4, 3, 2)
                }
            }
        };

        private readonly Dictionary<string, int> _levels = new();

        public event Action OnUpgradeChanged;

        public int GetLevel(string upgradeId) =>
            _levels.TryGetValue(upgradeId, out int lvl) ? lvl : 0;

        /// <summary>Attempt to purchase an upgrade. Returns true if successful.</summary>
        public bool TryUpgrade(string upgradeId)
        {
            var def = Array.Find(Upgrades, u => u.Id == upgradeId);
            if (def == null) return false;

            int currentLevel = GetLevel(upgradeId);
            if (currentLevel >= def.MaxLevel) return false;

            var cost = def.Costs[currentLevel];
            if (!inventory.TrySpend(cost)) return false;

            _levels[upgradeId] = currentLevel + 1;
            ApplyUpgrades();
            OnUpgradeChanged?.Invoke();
            return true;
        }

        /// <summary>Apply all current upgrade levels to game systems.</summary>
        public void ApplyUpgrades()
        {
            if (energySystem != null)
                energySystem.CapacityMultiplier = 1f + GetLevel("battery") * GetDef("battery").BonusPerLevel;

            if (vehicleController != null)
            {
                vehicleController.DriveMultiplier = 1f + GetLevel("drive") * GetDef("drive").BonusPerLevel;
            }

            // Cooling is applied in HazardSystem

            if (poiManager != null)
                poiManager.RadarMultiplier = 1f + GetLevel("radar") * GetDef("radar").BonusPerLevel;

            if (fogOfWar != null)
                fogOfWar.VisionMultiplier = 1f + GetLevel("radar") * GetDef("radar").BonusPerLevel * 0.5f;

            if (inventory != null)
                inventory.CargoMultiplier = 1f + GetLevel("cargo") * GetDef("cargo").BonusPerLevel;
        }

        public float GetCoolingMultiplier() =>
            1f + GetLevel("cooling") * GetDef("cooling").BonusPerLevel;

        /// <summary>Save state as dictionary for SaveManager.</summary>
        public Dictionary<string, int> SaveState() => new(_levels);

        public void LoadState(Dictionary<string, int> state)
        {
            _levels.Clear();
            foreach (var kv in state)
                _levels[kv.Key] = kv.Value;
            ApplyUpgrades();
        }

        private static UpgradeDefinition GetDef(string id) =>
            Array.Find(Upgrades, u => u.Id == id);

        private static Dictionary<ResourceType, int> Cost(int scrap, int electronics, int fuel, int water)
        {
            var dict = new Dictionary<ResourceType, int>();
            if (scrap > 0) dict[ResourceType.Scrap] = scrap;
            if (electronics > 0) dict[ResourceType.Electronics] = electronics;
            if (fuel > 0) dict[ResourceType.Fuel] = fuel;
            if (water > 0) dict[ResourceType.Water] = water;
            return dict;
        }
    }

    [Serializable]
    public class UpgradeDefinition
    {
        public string Id;
        public string Name;
        public string Description;
        public int MaxLevel;
        public float BonusPerLevel;
        public Dictionary<ResourceType, int>[] Costs;
    }
}
