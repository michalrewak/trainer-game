using System.Collections.Generic;
using DesertSurvival.Progression;
using DesertSurvival.Session;
using DesertSurvival.World;
using UnityEngine;
using UnityEngine.UI;

namespace DesertSurvival.UI
{
    /// <summary>
    /// Base menu UI — Fallout terminal style (monospaced font, CRT scanlines).
    /// Shows upgrades, resources, and session stats.
    /// Only active when player is at base.
    /// </summary>
    public class BaseMenuController : MonoBehaviour
    {
        [Header("References")]
        [SerializeField] private ExpeditionManager expedition;
        [SerializeField] private UpgradeManager upgradeManager;
        [SerializeField] private InventoryManager inventory;
        [SerializeField] private SaveManager saveManager;

        [Header("UI — Panel")]
        [SerializeField] private GameObject menuPanel;

        [Header("UI — Resources")]
        [SerializeField] private Text scrapText;
        [SerializeField] private Text electronicsText;
        [SerializeField] private Text fuelText;
        [SerializeField] private Text waterText;

        [Header("UI — Upgrades")]
        [SerializeField] private Transform upgradeListParent;
        [SerializeField] private GameObject upgradeRowPrefab;

        [Header("UI — Stats")]
        [SerializeField] private Text totalSessionsText;
        [SerializeField] private Text totalPedalTimeText;

        private readonly List<GameObject> _upgradeRows = new();

        private void Update()
        {
            bool atBase = expedition != null && expedition.State == ExpeditionState.AtBase;

            if (menuPanel != null && menuPanel.activeSelf != atBase)
                menuPanel.SetActive(atBase);

            if (!atBase) return;

            UpdateResources();
            UpdateStats();
        }

        private void OnEnable()
        {
            RebuildUpgradeList();
            if (upgradeManager != null)
                upgradeManager.OnUpgradeChanged += RebuildUpgradeList;
            if (inventory != null)
                inventory.OnInventoryChanged += UpdateResources;
        }

        private void OnDisable()
        {
            if (upgradeManager != null)
                upgradeManager.OnUpgradeChanged -= RebuildUpgradeList;
            if (inventory != null)
                inventory.OnInventoryChanged -= UpdateResources;
        }

        private void UpdateResources()
        {
            if (inventory == null) return;
            if (scrapText != null) scrapText.text = $"ZLOM:        {inventory.GetAmount(ResourceType.Scrap)}";
            if (electronicsText != null) electronicsText.text = $"ELEKTRONIKA: {inventory.GetAmount(ResourceType.Electronics)}";
            if (fuelText != null) fuelText.text = $"PALIWO:      {inventory.GetAmount(ResourceType.Fuel)}";
            if (waterText != null) waterText.text = $"WODA:        {inventory.GetAmount(ResourceType.Water)}";
        }

        private void UpdateStats()
        {
            if (saveManager == null) return;

            if (totalSessionsText != null)
                totalSessionsText.text = $"WYPRAWY: {saveManager.TotalSessions}";

            if (totalPedalTimeText != null)
            {
                float t = saveManager.TotalPedalTimeSeconds;
                int h = Mathf.FloorToInt(t / 3600f);
                int m = Mathf.FloorToInt((t % 3600f) / 60f);
                totalPedalTimeText.text = $"CZAS PEDALOWANIA: {h}h {m}m";
            }
        }

        private void RebuildUpgradeList()
        {
            if (upgradeListParent == null || upgradeRowPrefab == null) return;

            // Clear old rows
            foreach (var row in _upgradeRows)
                Destroy(row);
            _upgradeRows.Clear();

            foreach (var def in UpgradeManager.Upgrades)
            {
                var row = Instantiate(upgradeRowPrefab, upgradeListParent);
                _upgradeRows.Add(row);

                int level = upgradeManager.GetLevel(def.Id);
                bool maxed = level >= def.MaxLevel;

                // Name + level
                var nameText = row.transform.Find("NameText")?.GetComponent<Text>();
                if (nameText != null)
                    nameText.text = $"{def.Name} [{level}/{def.MaxLevel}]";

                // Description
                var descText = row.transform.Find("DescText")?.GetComponent<Text>();
                if (descText != null)
                    descText.text = def.Description;

                // Cost
                var costText = row.transform.Find("CostText")?.GetComponent<Text>();
                if (costText != null)
                {
                    if (maxed)
                    {
                        costText.text = "MAX";
                    }
                    else
                    {
                        var cost = def.Costs[level];
                        var parts = new List<string>();
                        foreach (var kv in cost)
                            parts.Add($"{kv.Key}: {kv.Value}");
                        costText.text = string.Join(" | ", parts);
                    }
                }

                // Button
                var button = row.transform.Find("UpgradeButton")?.GetComponent<Button>();
                if (button != null)
                {
                    string id = def.Id; // Capture for closure
                    button.interactable = !maxed && inventory.HasResources(def.Costs[level]);
                    button.onClick.AddListener(() => OnUpgradeClicked(id));
                }
            }
        }

        private void OnUpgradeClicked(string upgradeId)
        {
            if (upgradeManager.TryUpgrade(upgradeId))
            {
                expedition.OnUpgradePurchased();
                RebuildUpgradeList();
            }
        }
    }
}
