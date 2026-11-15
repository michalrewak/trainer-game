using UnityEngine;

namespace DesertSurvival.World
{
    /// <summary>
    /// Types of resources that can be collected in the desert.
    /// </summary>
    public enum ResourceType
    {
        Scrap,        // Złom — basic building material
        Electronics,  // Elektronika — advanced upgrades
        Fuel,         // Paliwo — energy boosts
        Water         // Woda — survival / cooling
    }

    /// <summary>
    /// A collectible resource pickup in the world.
    /// Player drives into it to collect.
    /// </summary>
    public class ResourcePickup : MonoBehaviour
    {
        [SerializeField] private ResourceType resourceType;
        [SerializeField] private int amount = 1;
        [SerializeField] private float bobSpeed = 2f;
        [SerializeField] private float bobHeight = 0.3f;

        public ResourceType Type => resourceType;
        public int Amount => amount;

        private Vector3 _startPos;
        private bool _collected;

        private void Start()
        {
            _startPos = transform.position;
        }

        private void Update()
        {
            if (_collected) return;

            // Simple hovering animation
            float offset = Mathf.Sin(Time.time * bobSpeed) * bobHeight;
            transform.position = _startPos + Vector3.up * offset;
        }

        private void OnTriggerEnter(Collider other)
        {
            if (_collected) return;

            var inventory = other.GetComponentInParent<Progression.InventoryManager>();
            if (inventory != null && inventory.TryAdd(resourceType, amount))
            {
                _collected = true;
                // TODO: Play pickup VFX/SFX
                Destroy(gameObject, 0.1f);
            }
        }
    }
}
