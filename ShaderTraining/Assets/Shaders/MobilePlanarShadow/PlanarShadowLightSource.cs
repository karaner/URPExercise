using UnityEngine;

namespace URPExercise
{
    /// <summary>
    /// Binds one scene light to one planar-shadow renderer.
    /// Leave Source Light empty to use URP's automatic main directional light.
    /// </summary>
    [ExecuteAlways]
    [DisallowMultipleComponent]
    [AddComponentMenu("URPExercise/Planar Shadow Light Source")]
    public sealed class PlanarShadowLightSource : MonoBehaviour
    {
        [Header("Light Binding")]
        [SerializeField]
        [Tooltip("留空时使用 URP 主平行光；也可指定平行光、点光或聚光灯。")]
        private Light sourceLight;

        [SerializeField]
        [Tooltip("使用平面阴影材质的 MeshRenderer 或 SkinnedMeshRenderer。")]
        private Renderer targetRenderer;

        private MaterialPropertyBlock propertyBlock;

        private static readonly int LightTypeId = Shader.PropertyToID("_LightType");
        private static readonly int LightPositionId = Shader.PropertyToID("_LightPositionWS");
        private static readonly int LightDirectionId = Shader.PropertyToID("_LightDirectionWS");
        private static readonly int SpotDirectionId = Shader.PropertyToID("_LightSpotDirectionWS");
        private static readonly int LightRangeId = Shader.PropertyToID("_LightRange");
        private static readonly int SpotInnerCosId = Shader.PropertyToID("_LightSpotInnerCos");
        private static readonly int SpotOuterCosId = Shader.PropertyToID("_LightSpotOuterCos");

        private void Reset()
        {
            targetRenderer = GetComponent<Renderer>();
        }

        private void OnEnable()
        {
            EnsureReferences();
            ApplyLight();
        }

        private void OnValidate()
        {
            EnsureReferences();
            ApplyLight();
        }

        private void LateUpdate()
        {
            ApplyLight();
        }

        /// <summary>
        /// Changes the bound light at runtime and immediately updates the shadow.
        /// </summary>
        public void SetSourceLight(Light light)
        {
            sourceLight = light;
            ApplyLight();
        }

        private void EnsureReferences()
        {
            if (targetRenderer == null)
            {
                targetRenderer = GetComponent<Renderer>();
            }

            if (propertyBlock == null)
            {
                propertyBlock = new MaterialPropertyBlock();
            }
        }

        private void ApplyLight()
        {
            EnsureReferences();
            if (targetRenderer == null)
            {
                return;
            }

            targetRenderer.GetPropertyBlock(propertyBlock);

            // No binding means the original automatic URP main-light mode.
            if (sourceLight == null)
            {
                targetRenderer.enabled = true;
                propertyBlock.SetFloat(LightTypeId, -1.0f);
                targetRenderer.SetPropertyBlock(propertyBlock);
                return;
            }

            bool supported = sourceLight.isActiveAndEnabled &&
                (sourceLight.type == LightType.Directional ||
                 sourceLight.type == LightType.Point ||
                 sourceLight.type == LightType.Spot);

            targetRenderer.enabled = supported;
            if (!supported)
            {
                return;
            }

            Transform lightTransform = sourceLight.transform;
            Vector3 position = lightTransform.position;

            switch (sourceLight.type)
            {
                case LightType.Directional:
                {
                    propertyBlock.SetFloat(LightTypeId, 0.0f);
                    Vector3 directionToLight = -lightTransform.forward;
                    propertyBlock.SetVector(
                        LightDirectionId,
                        new Vector4(directionToLight.x, directionToLight.y, directionToLight.z, 0.0f)
                    );
                    break;
                }

                case LightType.Point:
                {
                    propertyBlock.SetFloat(LightTypeId, 1.0f);
                    SetLocalLight(position);
                    break;
                }

                case LightType.Spot:
                {
                    propertyBlock.SetFloat(LightTypeId, 2.0f);
                    SetLocalLight(position);

                    Vector3 spotDirection = lightTransform.forward;
                    propertyBlock.SetVector(
                        SpotDirectionId,
                        new Vector4(spotDirection.x, spotDirection.y, spotDirection.z, 0.0f)
                    );

                    // URP/HDRP expose inner spot data differently. For this
                    // stylized shadow, use a soft inner cone at 80% of the
                    // outer half-angle without requiring additional packages.
                    float outerHalfAngle = Mathf.Clamp(sourceLight.spotAngle, 0.1f, 179.0f)
                        * 0.5f * Mathf.Deg2Rad;
                    float innerHalfAngle = outerHalfAngle * 0.8f;
                    propertyBlock.SetFloat(SpotOuterCosId, Mathf.Cos(outerHalfAngle));
                    propertyBlock.SetFloat(SpotInnerCosId, Mathf.Cos(innerHalfAngle));
                    break;
                }
            }

            targetRenderer.SetPropertyBlock(propertyBlock);
        }

        private void SetLocalLight(Vector3 position)
        {
            propertyBlock.SetVector(
                LightPositionId,
                new Vector4(position.x, position.y, position.z, 1.0f)
            );
            propertyBlock.SetFloat(LightRangeId, Mathf.Max(sourceLight.range, 0.001f));
        }
    }
}
