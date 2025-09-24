Shader "Custom/PBRShader"
{
    Properties
    {
        _BaseColor("Base Color",Color) = (1,1,1,1)
        _DiffuseTex("Base Tex",2D) = "white"{}
        
        [NoScaleOffset][Normal]_NormalTex("Normal Tex",2D) = "bump"{}
        [NoScaleOffset]_NormalScale("Normal Scale",Float) = 1
        
        [NoScaleOffset]_MaskTex("RGB is Metallic,A is Roughness",2D) = "white"{}
        _Roughness("Roughness",Range(0,1)) = 1
        _Metallic("Metallic",Range(0,1)) = 1
        
        [Toggle(_Emission_On)] _ToggleEmission("Enable Emission",Float) = 1
        [NoScaleOffset]_EmissionTex("EmissionTex",2D) = "white"{} 
        [HDR]_EmissionCol("Emission Color",Color) = (0,0,0,1)
        [Toggle(_Animate_On)] _ToggleAnimate("Enable Emission Animate",Float) = 0
        _EmissionSpeed("Emission Anime Speed",Float) = 1
        _EmissionWave("Emission Wave",Float) = 1
        
        _AO("AO",Float) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 200
        
        HLSLINCLUDE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "PbrData.hlsl"

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS                
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE            
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS                        
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS    
            #pragma multi_compile _ _SHADOWS_SOFT                         

            
            #pragma shader_feature _Emission_On
            #pragma shader_feature _Animate_On

            CBUFFER_START(UnityPerMaterial)
                float4 _DiffuseTex_ST;
                float4 _Diffuse;
                float4 _BaseColor;

                float _NormalScale, _Metallic, _Roughness;
                
                float4 _EmissionCol;
                float _EmissionSpeed, _EmissionWave;
            
                float4 _AO;
                
            CBUFFER_END

            TEXTURE2D(_DiffuseTex); SAMPLER(sampler_DiffuseTex);
            TEXTURE2D(_NormalTex);  SAMPLER(sampler_NormalTex);
            TEXTURE2D(_MaskTex);    SAMPLER(sampler_MaskTex);
            TEXTURE2D(_EmissionTex); SAMPLER(sampler__EmissionTex);
            
            struct appdata
            {
                float4 positionOS : POSITION;
                float4 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : NORMAL;
                float3 tangentWS : TANGENT;
                float3 bitTangentWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
            };
        ENDHLSL
        

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            
            HLSLPROGRAM

            #pragma vertex vert;
            #pragma fragment frag;

            v2f vert(appdata v)
            {
                v2f o;
                o.uv = TRANSFORM_TEX(v.texcoord,_DiffuseTex);
                
                VertexPositionInputs positionInput = GetVertexPositionInputs(v.positionOS);
                o.positionCS = positionInput.positionCS;
                o.positionWS = positionInput.positionWS;

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS.xyz,v.tangentOS);
                o.normalWS = normalInput.normalWS;
                o.tangentWS = normalInput.tangentWS;
                o.bitTangentWS = normalInput.bitangentWS;
            
                o.viewDirWS = GetWorldSpaceNormalizeViewDir(o.positionWS);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_DiffuseTex,sampler_DiffuseTex,i.uv) * _BaseColor;
                half4 normal = SAMPLE_TEXTURE2D(_NormalTex,sampler_NormalTex,i.uv);
                half4 mask = SAMPLE_TEXTURE2D(_MaskTex,sampler_MaskTex,i.uv);
                
                #ifdef _Emission_On
                    half4 emission = SAMPLE_TEXTURE2D(_EmissionTex,sampler__EmissionTex,i.uv);
                    float3 emissive = emission * _EmissionCol;
                    #ifdef _Animate_On
                    emissive *= (sin(_Time.y * _EmissionSpeed) + 1) * _EmissionWave;
                    #endif
                #else
                    float3 emissive = 0;
                #endif
                
                float metallic = mask.r * _Metallic;
                float roughness = mask.a * _Roughness;
                
                //法线
                float3x3 tbn = {i.tangentWS, i.bitTangentWS, i.normalWS};
                tbn = transpose(tbn);
                float3 normalWS = UnpackNormalScale(normal,_NormalScale);
                normalWS = normalize(mul(tbn,normalWS));

                half ao = lerp(1,mask.b,_AO);
                
                
                float3 finalCol = PBR(i.viewDirWS,normalWS,i.positionWS,albedo,roughness,metallic,ao,emissive);

                float3 additionCol = 0;
                
                int pixelLightCount = GetAdditionalLightsCount();
                for (int index = 0; index < pixelLightCount ; index ++)
                {
                    Light light = GetAdditionalLight(index,i.positionWS);
                    additionCol += PBRDirectLightResult(light,i.viewDirWS,normalWS,albedo,roughness,metallic);
                }
                finalCol += additionCol;
                return float4(finalCol,1);
            }
            
            ENDHLSL
        }
    Pass
    {
        Tags
        {
            "LightMode" = "ShadowCaster"
        }
        HLSLPROGRAM

        #pragma vertex vertshadow
        #pragma fragment fragshadow

        v2f vertshadow(appdata v)
        {
            v2f o;

            float3 posWS = TransformObjectToWorld(v.positionOS);
            float3 norWS = TransformObjectToWorldNormal(v.normalOS);
            Light MainLight = GetMainLight();
            
            o.positionCS = TransformWorldToHClip(ApplyShadowBias(posWS,norWS,MainLight.direction)); 

            #if UNITY_REVERSED_Z
            o.positionCS.z - min(o.positionCS.z,o.positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #else
            o.positionCS.z - max(o.positionCS.z,o.positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #endif
            
            return o;
        }

        float4 fragshadow(v2f i) : SV_Target
        {
            float4 color;
            color.xyz = float3(0,0,0);
            return color;
        }
        ENDHLSL
    }
    }
    CustomEditor "PBRShaderGUI"
}
