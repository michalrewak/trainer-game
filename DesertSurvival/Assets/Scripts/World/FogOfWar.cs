using UnityEngine;

namespace DesertSurvival.World
{
    /// <summary>
    /// Simple grid-based fog of war. Unexplored areas are covered.
    /// As the player drives around, cells within view range are revealed.
    /// Rendered as a projector/overlay on the terrain.
    /// </summary>
    public class FogOfWar : MonoBehaviour
    {
        [Header("Grid")]
        [SerializeField] private int gridSize = 128;
        [SerializeField] private float worldSize = 2000f; // meters per side

        [Header("Reveal")]
        [SerializeField] private float revealRadius = 40f;

        private Texture2D _fogTexture;
        private Color32[] _pixels;
        private bool _dirty;

        public Texture2D FogTexture => _fogTexture;

        /// <summary>Upgrade: vision range multiplier.</summary>
        public float VisionMultiplier { get; set; } = 1f;

        private void Awake()
        {
            _fogTexture = new Texture2D(gridSize, gridSize, TextureFormat.Alpha8, false)
            {
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };

            _pixels = new Color32[gridSize * gridSize];
            // Start fully fogged
            for (int i = 0; i < _pixels.Length; i++)
                _pixels[i] = new Color32(0, 0, 0, 255);

            _fogTexture.SetPixels32(_pixels);
            _fogTexture.Apply();
        }

        /// <summary>Reveal area around world position.</summary>
        public void RevealAt(Vector3 worldPos)
        {
            float cellSize = worldSize / gridSize;
            float radius = revealRadius * VisionMultiplier;
            int cellRadius = Mathf.CeilToInt(radius / cellSize);

            // Convert world pos to grid coords (assuming world centered at 0,0)
            int cx = Mathf.FloorToInt((worldPos.x + worldSize * 0.5f) / cellSize);
            int cy = Mathf.FloorToInt((worldPos.z + worldSize * 0.5f) / cellSize);

            for (int y = cy - cellRadius; y <= cy + cellRadius; y++)
            {
                for (int x = cx - cellRadius; x <= cx + cellRadius; x++)
                {
                    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) continue;

                    float dx = (x - cx) * cellSize;
                    float dy = (y - cy) * cellSize;
                    if (dx * dx + dy * dy > radius * radius) continue;

                    int idx = y * gridSize + x;
                    if (_pixels[idx].a > 0)
                    {
                        _pixels[idx] = new Color32(0, 0, 0, 0); // Revealed
                        _dirty = true;
                    }
                }
            }
        }

        private void LateUpdate()
        {
            if (!_dirty) return;
            _fogTexture.SetPixels32(_pixels);
            _fogTexture.Apply();
            _dirty = false;
        }

        /// <summary>Returns exploration percentage (0-1).</summary>
        public float GetExplorationPercent()
        {
            int revealed = 0;
            for (int i = 0; i < _pixels.Length; i++)
            {
                if (_pixels[i].a == 0) revealed++;
            }
            return (float)revealed / _pixels.Length;
        }

        /// <summary>Save/load fog state as byte array for save system.</summary>
        public byte[] SaveState()
        {
            byte[] state = new byte[_pixels.Length];
            for (int i = 0; i < _pixels.Length; i++)
                state[i] = _pixels[i].a;
            return state;
        }

        public void LoadState(byte[] state)
        {
            if (state.Length != _pixels.Length) return;
            for (int i = 0; i < _pixels.Length; i++)
                _pixels[i] = new Color32(0, 0, 0, state[i]);
            _dirty = true;
        }
    }
}
