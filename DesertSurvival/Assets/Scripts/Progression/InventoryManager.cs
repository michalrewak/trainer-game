using System;
using System.Collections.Generic;
using DesertSurvival.World;
using UnityEngine;

namespace DesertSurvival.Progression
{
    /// <summary>
    /// Manages the player's resource inventory with cargo capacity limits.
    /// </summary>
    public class InventoryManager : MonoBehaviour
    {
        [SerializeField] private int maxCargoSlots = 10;

        private readonly Dictionary<ResourceType, int> _resources = new();

        /// <summary>Upgrade: cargo multiplier.</summary>
        public float CargoMultiplier { get; set; } = 1f;

        public int MaxCargo => Mathf.RoundToInt(maxCargoSlots * CargoMultiplier);
        public int UsedCargo { get; private set; }
        public int FreeCargo => MaxCargo - UsedCargo;

        public event Action OnInventoryChanged;

        public int GetAmount(ResourceType type)
        {
            return _resources.TryGetValue(type, out int amount) ? amount : 0;
        }

        /// <summary>Try to add resources. Returns false if cargo is full.</summary>
        public bool TryAdd(ResourceType type, int amount)
        {
            if (amount <= 0) return false;
            if (UsedCargo + amount > MaxCargo) return false;

            if (!_resources.ContainsKey(type))
                _resources[type] = 0;

            _resources[type] += amount;
            UsedCargo += amount;
            OnInventoryChanged?.Invoke();
            return true;
        }

        /// <summary>Remove resources. Returns false if not enough.</summary>
        public bool TryRemove(ResourceType type, int amount)
        {
            if (amount <= 0) return false;
            if (GetAmount(type) < amount) return false;

            _resources[type] -= amount;
            UsedCargo -= amount;
            if (_resources[type] == 0)
                _resources.Remove(type);

            OnInventoryChanged?.Invoke();
            return true;
        }

        /// <summary>Check if player has enough of each resource.</summary>
        public bool HasResources(Dictionary<ResourceType, int> cost)
        {
            foreach (var kv in cost)
            {
                if (GetAmount(kv.Key) < kv.Value)
                    return false;
            }
            return true;
        }

        /// <summary>Spend resources (for upgrades). Returns false if insufficient.</summary>
        public bool TrySpend(Dictionary<ResourceType, int> cost)
        {
            if (!HasResources(cost)) return false;

            foreach (var kv in cost)
                TryRemove(kv.Key, kv.Value);

            return true;
        }

        /// <summary>Returns a copy of current resources for UI.</summary>
        public Dictionary<ResourceType, int> GetAll()
        {
            return new Dictionary<ResourceType, int>(_resources);
        }
    }
}
