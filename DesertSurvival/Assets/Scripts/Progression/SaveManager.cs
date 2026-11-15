using System;
using System.Collections.Generic;
using System.IO;
using DesertSurvival.World;
using UnityEngine;

namespace DesertSurvival.Progression
{
    /// <summary>
    /// Saves and loads game state to a local JSON file.
    /// </summary>
    public class SaveManager : MonoBehaviour
    {
        [SerializeField] private UpgradeManager upgradeManager;
        [SerializeField] private InventoryManager inventory;
        [SerializeField] private FogOfWar fogOfWar;

        private string SavePath => Path.Combine(Application.persistentDataPath, "save.json");

        public void Save()
        {
            var data = new SaveData
            {
                upgradeLevels = upgradeManager.SaveState(),
                resources = inventory.GetAll(),
                fogState = fogOfWar != null ? Convert.ToBase64String(fogOfWar.SaveState()) : null,
                totalSessions = _totalSessions,
                totalPedalTimeSeconds = _totalPedalTime
            };

            string json = JsonUtility.ToJson(new SaveDataWrapper(data), true);
            File.WriteAllText(SavePath, json);
            Debug.Log($"[Save] Game saved to {SavePath}");
        }

        public bool Load()
        {
            if (!File.Exists(SavePath)) return false;

            try
            {
                string json = File.ReadAllText(SavePath);
                var wrapper = JsonUtility.FromJson<SaveDataWrapper>(json);
                var data = wrapper.ToSaveData();

                upgradeManager.LoadState(data.upgradeLevels);

                // Restore resources — add to empty inventory
                foreach (var kv in data.resources)
                    inventory.TryAdd(kv.Key, kv.Value);

                if (!string.IsNullOrEmpty(data.fogState) && fogOfWar != null)
                    fogOfWar.LoadState(Convert.FromBase64String(data.fogState));

                _totalSessions = data.totalSessions;
                _totalPedalTime = data.totalPedalTimeSeconds;

                Debug.Log("[Save] Game loaded.");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Save] Load failed: {ex.Message}");
                return false;
            }
        }

        // Session tracking
        private int _totalSessions;
        private float _totalPedalTime;

        public void RecordSession(float pedalTimeSeconds)
        {
            _totalSessions++;
            _totalPedalTime += pedalTimeSeconds;
        }

        public int TotalSessions => _totalSessions;
        public float TotalPedalTimeSeconds => _totalPedalTime;
    }

    /// <summary>
    /// Serializable save data. Since Unity's JsonUtility doesn't support Dictionary,
    /// we use a wrapper with parallel arrays.
    /// </summary>
    [Serializable]
    public class SaveData
    {
        public Dictionary<string, int> upgradeLevels;
        public Dictionary<ResourceType, int> resources;
        public string fogState;
        public int totalSessions;
        public float totalPedalTimeSeconds;
    }

    [Serializable]
    public class SaveDataWrapper
    {
        public string[] upgradeIds;
        public int[] upgradeLvls;
        public int[] resourceTypes;
        public int[] resourceAmounts;
        public string fogState;
        public int totalSessions;
        public float totalPedalTimeSeconds;

        public SaveDataWrapper() { }

        public SaveDataWrapper(SaveData data)
        {
            var uKeys = new List<string>(data.upgradeLevels.Keys);
            var uVals = new List<int>(data.upgradeLevels.Values);
            upgradeIds = uKeys.ToArray();
            upgradeLvls = uVals.ToArray();

            var rKeys = new List<int>();
            var rVals = new List<int>();
            foreach (var kv in data.resources)
            {
                rKeys.Add((int)kv.Key);
                rVals.Add(kv.Value);
            }
            resourceTypes = rKeys.ToArray();
            resourceAmounts = rVals.ToArray();

            fogState = data.fogState;
            totalSessions = data.totalSessions;
            totalPedalTimeSeconds = data.totalPedalTimeSeconds;
        }

        public SaveData ToSaveData()
        {
            var upgrades = new Dictionary<string, int>();
            if (upgradeIds != null)
            {
                for (int i = 0; i < upgradeIds.Length; i++)
                    upgrades[upgradeIds[i]] = upgradeLvls[i];
            }

            var resources = new Dictionary<ResourceType, int>();
            if (resourceTypes != null)
            {
                for (int i = 0; i < resourceTypes.Length; i++)
                    resources[(ResourceType)resourceTypes[i]] = resourceAmounts[i];
            }

            return new SaveData
            {
                upgradeLevels = upgrades,
                resources = resources,
                fogState = fogState,
                totalSessions = totalSessions,
                totalPedalTimeSeconds = totalPedalTimeSeconds
            };
        }
    }
}
