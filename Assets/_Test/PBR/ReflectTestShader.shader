Shader "Custom/MyReflectionShader"
{
    Properties
    {
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        // ... 其他属性
    }
    
    SubShader
    {
        
        
        
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Pass
        {
            
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM

            float4 _Smoothness;
            
            #pragma vertex vert
            #pragma fragment frag
            
            // 关键：反射探针相关编译指令
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            
            // 包含必要的头文件
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 viewDirWS : TEXCOORD1;
            };
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertex = GetVertexPositionInputs(input.positionOS);
                output.positionCS = vertex.positionCS;
                output.normalWS =  mul(unity_ObjectToWorld,input.normalOS);
                output.viewDirWS = GetCameraPositionWS() - vertex.positionWS;
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                // 准备反射计算所需的参数
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = normalize(input.viewDirWS);
                float perceptualRoughness = 1.0 - _Smoothness;
                
                // 计算反射向量
                float3 reflectVector = reflect(-viewDirWS, normalWS);
                
                // 采样反射探针
                half3 reflection = GlossyEnvironmentReflection(reflectVector, 
                    perceptualRoughness, 1.0);
                
                // 使用反射颜色
                half4 color = half4(reflection, 1.0);
                return color;
            }
            ENDHLSL
        }
    }
}