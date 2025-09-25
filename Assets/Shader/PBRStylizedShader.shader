Shader "Unlit/PBR2"
{
    Properties
    {
        _DiffuseColor("Diffuse Color",Color) = (1,1,1)
        _DiffuseTex("Diffuse Map",2D) = "white"{}
        
        [Normal][NoScaleOffset] _NormalTex("Normal Map",2D) = "bump"{}
        _NormalScale("Normal Scale",Float) = 1
        
        [NoScaleOffset] _MRTex("Metallic Map",2D) = "white"{}
        _Metallic("Metallic",Float) = 0
        _Roughness("Roughness",Float) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _DiffuseTex_ST;  float4 _DiffuseColor;
            float4 _NormalTex_ST;   float _NormalScale;
            float4 _MRTex_ST;       float _Metallic;    float _Roughness;
        CBUFFER_END

        TEXTURE2D(_DiffuseTex);     SAMPLER(sampler_DiffuseTex);
        TEXTURE2D(_NormalTex);      SAMPLER(sampler_NormalTex);
        TEXTURE2D(_MRTex);          SAMPLER(sampler_MRTex);
        
        struct Attribute
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float2 texcoord : TEXCOORD0;
            float4 tangentOS : TANGENT;
        };

        struct Varying
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS : TEXCOORD2;
            float3 tangetWS : TEXCOORD3;
            float3 bitTangetWS : TEXCOORD4;
            float3 viewDirWS : TEXCOORD5;
        };
        ENDHLSL

        Pass
        {
            
        Tags
        {
            "LightMode" = "UniversalForward"
        }
        
        HLSLPROGRAM

        #pragma vertex vert
        #pragma fragment frag

        Varying vert(Attribute v)
        {
            Varying o = (Varying)0;
            
            o.uv = TRANSFORM_TEX(v.texcoord,_DiffuseTex);
            VertexPositionInputs positonInput = GetVertexPositionInputs(v.positionOS);
            o.positionCS = positonInput.positionCS;
            o.positionWS = positonInput.positionWS;

            VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS);
            o.normalWS = normalInput.normalWS;
            o.tangetWS = normalInput.tangentWS;
            o.bitTangetWS = normalInput.bitangentWS;

            //o.viewDirWs = GetWorldSpaceViewDir(o.positionWS);
            o.viewDirWS = GetCameraPositionWS() - o.positionWS;

            return o;
        }

        //法线分布函数
        /*
         *
         *
         */
        float Distribution(float roughness ,float nh)
        {
            //float lerpSquareRoughness = pow(roughness,2); 和下面的公式类似，但我们通过lerp函数进行了一个微小的重映射，保证roughness不为0
            float lerpSquareRoughness = pow(lerp(0.01,1,roughness),2);
            
            float D = lerpSquareRoughness / (pow((pow(nh,2) * (lerpSquareRoughness - 1) + 1),2) * PI);
            return D;
        }

        half4 frag(Varying i) : SV_Target
        {
            half4 albedo = SAMPLE_TEXTURE2D(_DiffuseTex,sampler_DiffuseTex,i.uv);
            half4 normal = SAMPLE_TEXTURE2D(_NormalTex,sampler_NormalTex,i.uv);
            half4 metalRough = SAMPLE_TEXTURE2D(_MRTex,sampler_MRTex,i.uv);
            
            float3x3 tbn = {i.tangetWS,i.bitTangetWS,i.normalWS};
            float3 normalTS = UnpackNormalScale(normal,_NormalScale);   //法线数据 颜色空间 > 切线空间 并进行NormalScale变换
            half3 N = NormalizeNormalPerPixel(mul(normalTS,tbn));       //法线 切线空间 > 世界空间 转换
            
            return float4(N,1);
        }

            
        ENDHLSL
        }
        
    }
}
























