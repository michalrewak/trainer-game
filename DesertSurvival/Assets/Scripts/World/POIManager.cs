using System.Collections.Generic;
using UnityEngine;

namespace DesertSurvival.World
{
    /// <summary>
    /// A Point of Interest on the desert map. Can contain resource pickups,
    /// hazards, or story elements.
    /// </summary>
    public class POI : MonoBehaviour
    {
        [SerializeField] private string poiName = "Unknown";
        [SerializeField] private POIType poiType;
        [SerializeField] private float discoveryRadius = 30f;
        [SerializeField] private bool discovered;

        public string Name => poiName;
        public POIType Type => poiType;
        public bool IsDiscovered => discovered;
        public float DiscoveryRadius => discoveryRadius;

        public void Discover()
        {
            if (discovered) return;
            discovered = true;
            // TODO: Notify FogOfWar + UI
        }
    }

    public enum POIType
    {
        Wreckage,    // Wrakowisko — scrap + electronics
        Oasis,       // Oaza — water + shelter
        Scrapyard,   // Złomowisko — lots of scrap
        Ruins,       // Ruiny — electronics + lore
        FuelCache    // Skrytka paliwowa — fuel
    }

    /// <summary>
    /// Manages all POIs on the map, tracks discovery, provides radar functionality.
    /// </summary>
    public class POIManager : MonoBehaviour
    {
        [SerializeField] private float radarRange = 100f;

        private readonly List<POI> _allPois = new();

        /// <summary>Upgrade: radar range multiplier.</summary>
        public float RadarMultiplier { get; set; } = 1f;

        public IReadOnlyList<POI> AllPOIs => _allPois;

        private void Awake()
        {
            // Collect all POIs in the scene
            _allPois.AddRange(FindObjectsOfType<POI>());
        }

        /// <summary>
        /// Check which POIs the player can discover based on position and radar range.
        /// Call this from ExpeditionManager each frame.
        /// </summary>
        public void UpdateDiscovery(Vector3 playerPosition)
        {
            float range = radarRange * RadarMultiplier;

            foreach (var poi in _allPois)
            {
                if (poi.IsDiscovered) continue;

                float dist = Vector3.Distance(playerPosition, poi.transform.position);
                if (dist <= poi.DiscoveryRadius || dist <= range)
                {
                    poi.Discover();
                }
            }
        }

        /// <summary>Returns undiscovered POIs within radar range (for minimap hints).</summary>
        public List<POI> GetNearbyUndiscovered(Vector3 playerPosition)
        {
            float range = radarRange * RadarMultiplier;
            var result = new List<POI>();

            foreach (var poi in _allPois)
            {
                if (poi.IsDiscovered) continue;
                if (Vector3.Distance(playerPosition, poi.transform.position) <= range)
                    result.Add(poi);
            }

            return result;
        }
    }
}
