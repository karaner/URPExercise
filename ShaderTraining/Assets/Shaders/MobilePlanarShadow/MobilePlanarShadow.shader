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

            // Prevent overlapping triangles in the same character from
            // blending repeatedly and creating a patchy, over-dark shadow.
            // Use one shared value per character; use different values for
            // different characters whose shadows can overlap.
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

            Varyings Vert(Attributes input)
            {
                Varyings output;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float heightAboveGround = max(positionWS.y - _GroundHeight, 0.0);

                // URP's main directional light points from the surface toward
                // the light. Project away from it along the light ray:
                // P' = P - L * ((P.y - planeY) / L.y).
                float3 lightDirectionWS = GetMainLight().direction;
                float directionLengthSq = dot(lightDirectionWS, lightDirectionWS);
                lightDirectionWS = directionLengthSq > 0.0001
                    ? lightDirectionWS * rsqrt(directionLengthSq)
                    : normalize(float3(-0.4, 0.8, 0.3));

                // Avoid a near-zero division when the light approaches the
                // horizon. Keep the directional light shining downward.
                float verticalDirection = max(lightDirectionWS.y, 0.1);
                float projectionDistance = heightAboveGround / verticalDirection;

                float3 projectedPositionWS;
                projectedPositionWS.xz = positionWS.xz
                    - lightDirectionWS.xz * projectionDistance * _ShadowLength;
                projectedPositionWS.y = _GroundHeight + _PlaneOffset;

                output.positionCS = TransformWorldToHClip(projectedPositionWS);
                output.fogFactor = ComputeFogFactor(output.positionCS.z);

                // Use the renderer pivot's XZ as the character's foot center.
                // Both coordinates describe the ground plane, so overlapping
                // source triangles produce the same fade at the same pixel.
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

                    // Full opacity before Fade Start, then smoothly approach
                    // Fade End Opacity. Beyond Fade End, smoothstep stays at 1,
                    // so the shadow keeps the requested residual opacity.
                    half fadeAmount = smoothstep(
                        _FadeStartDistance,
                        fadeEnd,
                        distanceToFoot
                    );
                    distanceFade = lerp(1.0h, _FadeEndOpacity, fadeAmount);
                }

                // Alpha depends only on the projected ground position, not on
                // the source triangle, so stencil-tested overlaps stay smooth.
                half alpha = _ShadowColor.a * _Opacity * distanceFade;
                alpha *= 1.0h - input.fogFactor;
                return half4(_ShadowColor.rgb, alpha);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
