Shader "URPExercise/Mobile Planar Shadow"
{
    Properties
    {
        _ShadowColor ("Shadow Color", Color) = (0.025, 0.03, 0.045, 1)
        _Opacity ("Opacity", Range(0.0, 1.0)) = 0.45
        _ShadowLength ("Shadow Length", Range(0.0, 3.0)) = 1.0
        _GroundHeight ("Ground Height (World Y)", Float) = 0.0
        _PlaneOffset ("Plane Offset", Range(0.0, 0.05)) = 0.01
        [Header(Distance Fade)]
        [Min(0.0)] _FadeStartDistance ("Fade Start Distance", Float) = 0.2
        [Min(0.0)] _FadeEndDistance ("Fade End Distance (0 = Off)", Float) = 2.0
        _FadeEndOpacity ("Fade End Opacity", Range(0.0, 1.0)) = 0.3
        [IntRange] _StencilRef ("Stencil Ref", Range(1, 255)) = 1

        // Per-light values are supplied by PlanarShadowLightSource.cs through
        // a MaterialPropertyBlock. The default -1 keeps automatic URP main
        // light behavior for existing materials and single-light renderers.
        [HideInInspector] _LightType ("Light Type", Float) = -1.0
        [HideInInspector] _LightPositionWS ("Light Position WS", Vector) = (0, 0, 0, 1)
        [HideInInspector] _LightDirectionWS ("Light Direction WS", Vector) = (0, 1, 0, 0)
        [HideInInspector] _LightSpotDirectionWS ("Spot Direction WS", Vector) = (0, -1, 0, 0)
        [HideInInspector] _LightRange ("Light Range", Float) = 1.0
        [HideInInspector] _LightSpotInnerCos ("Spot Inner Cos", Float) = 0.9
        [HideInInspector] _LightSpotOuterCos ("Spot Outer Cos", Float) = 0.8
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent-100"
        }

        Pass
        {
            Name "PlanarShadow"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off
            Offset -1, -1

            // Parts of the same character under the same light share one ref.
            // Use a different ref for each character/light pair whose shadows
            // can overlap, so separate lights can still darken each other.
            Stencil
            {
                Ref [_StencilRef]
                Comp NotEqual
                Pass Replace
            }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ShadowColor;
                float _Opacity;
                float _ShadowLength;
                float _GroundHeight;
                float _PlaneOffset;
                float _FadeStartDistance;
                float _FadeEndDistance;
                float _FadeEndOpacity;
                float _StencilRef;
                float _LightType;
                float4 _LightPositionWS;
                float4 _LightDirectionWS;
                float4 _LightSpotDirectionWS;
                float _LightRange;
                float _LightSpotInnerCos;
                float _LightSpotOuterCos;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half fogFactor : TEXCOORD0;
                float2 shadowPositionXZ : TEXCOORD1;
                float2 footPositionXZ : TEXCOORD2;
            };

            float3 PlanarNormalize(float3 value, float3 fallback)
            {
                float lengthSq = dot(value, value);
                return lengthSq > 0.000001 ? value * rsqrt(lengthSq) : fallback;
            }

            float3 GetProjectionLightDirection(float3 positionWS)
            {
                // -1: automatic URP main directional light.
                if (_LightType < -0.5)
                {
                    return PlanarNormalize(
                        GetMainLight().direction,
                        float3(-0.4, 0.8, 0.3)
                    );
                }

                // 0: explicitly assigned directional light. Its direction
                // points from the receiver toward the light.
                if (_LightType < 0.5)
                {
                    return PlanarNormalize(
                        _LightDirectionWS.xyz,
                        float3(-0.4, 0.8, 0.3)
                    );
                }

                // 1/2: point or spot light. Unlike a directional light, the
                // direction toward a local light varies for every vertex.
                return PlanarNormalize(
                    _LightPositionWS.xyz - positionWS,
                    float3(0.0, 1.0, 0.0)
                );
            }

            half GetReceiverLightAttenuation(float3 receiverPositionWS)
            {
                // Automatic and explicit directional lights have no local
                // range or spot-cone attenuation.
                if (_LightType < 0.5)
                {
                    return 1.0h;
                }

                float3 lightToReceiver = receiverPositionWS - _LightPositionWS.xyz;
                float distanceToLight = length(lightToReceiver);
                float lightRange = max(_LightRange, 0.001);

                // Fade over the last 20 percent of the local light's range.
                half attenuation = 1.0h - smoothstep(
                    lightRange * 0.8,
                    lightRange,
                    distanceToLight
                );

                if (_LightType > 1.5)
                {
                    float3 receiverDirection = PlanarNormalize(
                        lightToReceiver,
                        float3(0.0, -1.0, 0.0)
                    );
                    float3 spotDirection = PlanarNormalize(
                        _LightSpotDirectionWS.xyz,
                        float3(0.0, -1.0, 0.0)
                    );
                    float cosAngle = dot(receiverDirection, spotDirection);
                    float outerCos = _LightSpotOuterCos;
                    float innerCos = max(_LightSpotInnerCos, outerCos + 0.0001);

                    attenuation *= smoothstep(outerCos, innerCos, cosAngle);
                }

                return attenuation;
            }

            Varyings Vert(Attributes input)
            {
                Varyings output;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float heightAboveGround = max(positionWS.y - _GroundHeight, 0.0);
                float3 lightDirectionWS = GetProjectionLightDirection(positionWS);

                // For every light type, L points from the vertex toward the
                // light, so the same projection equation can be reused:
                // P' = P - L * ((P.y - planeY) / L.y).
                // Keep local lights above the mesh and the ground plane.
                float verticalDirection = max(lightDirectionWS.y, 0.1);
                float projectionDistance = heightAboveGround / verticalDirection;

                float3 projectedPositionWS;
                projectedPositionWS.xz = positionWS.xz
                    - lightDirectionWS.xz * projectionDistance * _ShadowLength;
                projectedPositionWS.y = _GroundHeight + _PlaneOffset;

                output.positionCS = TransformWorldToHClip(projectedPositionWS);
                output.fogFactor = ComputeFogFactor(output.positionCS.z);

                // Use the renderer pivot's XZ as the character's foot center.
                float3 footPositionWS = TransformObjectToWorld(float3(0.0, 0.0, 0.0));
                output.shadowPositionXZ = projectedPositionWS.xz;
                output.footPositionXZ = footPositionWS.xz;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half distanceFade = 1.0h;
                if (_FadeEndDistance > 0.0001)
                {
                    float distanceToFoot = distance(
                        input.shadowPositionXZ,
                        input.footPositionXZ
                    );
                    float fadeEnd = max(
                        _FadeEndDistance,
                        _FadeStartDistance + 0.001
                    );

                    half fadeAmount = smoothstep(
                        _FadeStartDistance,
                        fadeEnd,
                        distanceToFoot
                    );
                    distanceFade = lerp(1.0h, _FadeEndOpacity, fadeAmount);
                }

                float3 receiverPositionWS = float3(
                    input.shadowPositionXZ.x,
                    _GroundHeight + _PlaneOffset,
                    input.shadowPositionXZ.y
                );
                half lightAttenuation = GetReceiverLightAttenuation(receiverPositionWS);

                // Distance, range and spot attenuation all depend only on the
                // projected ground position, not on the source triangle.
                half alpha = _ShadowColor.a * _Opacity * distanceFade;
                alpha *= lightAttenuation * (1.0h - input.fogFactor);

                // Fully transparent fragments should not reserve stencil.
                clip(alpha - 0.0001h);
                return half4(_ShadowColor.rgb, alpha);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
