Shader "Unlit/PBRStylized"
{
    Properties
    {
        _DiffuseColor("Diffuse Color",Color) = (1,1,1)
        _DiffuseTex("Diffuse Map",2D) = "white"{}
        
        [Normal][NoScaleOffset] _NormalTex("Normal Map",2D) = "bump"{}
        _NormalScale("Normal Scale",Float) = 1
        
        [NoScaleOffset] _MRTex("Metallic Map",2D) = "white"{}
        _Metallic("Metallic",Range(0,1)) = 0
        _Roughness("Roughness",Range(0,1)) = 1
        
        _CubeMapTex("CubeMap",Cube) = "_Skybox"{}
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
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        //#include "Assets/_Test/PBR/PbrData.hlsl"

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
        float Distribution(float roughness ,float3 normalDir,float3 halfDir)
        {
            float NdotH = max(saturate(dot(normalDir,halfDir)),0.01);
            
            float lerpSquareRoughness = pow(lerp(0.01,1,roughness),2);
            float D = lerpSquareRoughness / (pow(pow(NdotH,2) * (lerpSquareRoughness - 1) + 1, 2) * PI);
            return D;
        }

        //几何遮蔽子项
        inline float G_sub(float3 normalDir,float3 anotherDir,float k)
        {
            float dotProduct = dot(normalDir,anotherDir);
            dotProduct = max(dotProduct,0);
            return dotProduct/lerp(dotProduct,1,k);
        }

        //几何遮蔽函数
        float Geometry(float roughness ,float3 normalDir,float3 viewDir,float3 lightDir)
        {
            //直接光
            //half k = pow(roughness + 1,2) / 8.0;
            //间接光
            //const float d = 1.0 / 8.0;
            //half k = pow(roughness,2) / d;
            
            //例子里使用直接光照
            //question
            float k = pow(roughness + 1 ,2) / 8;

            float G1 = G_sub(normalDir,viewDir,k);
            float G2 = G_sub(normalDir,lightDir,k);

            float G = G1 * G2;
            
            return G;
        }

        //菲涅耳函数
        float3 FresnelEquation(float3 f0,float3 lightDir ,float3 halfDir)
        {
            float hl = max(saturate(dot(halfDir, lightDir)), 0.0001);
            float3 F = f0 + (1 - f0) * exp2((-5.55473 * hl - 6.98316) * hl);
            return F;
        }

        //球型光照，获取球协函数的光照信息
        float3 SH_IndirectionDiffuse(float3 normalWS)
        {
            real4 SHCoefficients[7];
            SHCoefficients[0] = unity_SHAr;
            SHCoefficients[1] = unity_SHAg;
            SHCoefficients[2] = unity_SHAb;
            SHCoefficients[3] = unity_SHBr;
            SHCoefficients[4] = unity_SHBg;
            SHCoefficients[5] = unity_SHBb;
            SHCoefficients[6] = unity_SHC;
            float3 color = SampleSH9(SHCoefficients,normalWS);
            return max(0,color);
        }

        //间接光菲涅耳
        float3 IndirF_Fuction(float NdotV ,float3 F0, float roughness)
        {
            float Fre = exp2((-5.55473 * NdotV - 6.98316) * NdotV);
            return F0 + Fre * saturate(1 - roughness - F0);
        }

        real3 IndirectSpeCube(float3 normalWS, float3 viewWS,float roughness,float AO)
        {
            float3 reflectDirWS = reflect(-viewWS,normalWS);
            roughness = roughness * (1.7 - 0.7 * roughness);
            float MidLevel = roughness * 6;
            float4 speColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0,samplerunity_SpecCube0,reflectDirWS,MidLevel);
            #if !defined(UNITY_USE_NATIVE_HDR)
                return DecodeHDREnvironment(speColor,1) * AO;
            #else
                return speColor.xyz * AO; 
            #endif
        }

        real3 IndirectSpeFactor(half roughness,half smoothness,half3 BRDFspe,half3 F0,half NdotV)
        {
            #ifdef UNITY_COLORSPACE_GAMMA
                half SurReduction = 1 - 0.28 * roughness * roughness;
            #else
                half SurReduction = 1 / (roughness * roughness + 1);
            #endif

            #if defined(SHADER_API_GLES)
                half Reflectivity = BRDFspe.x;
            #else
                half Reflectivity = max(max(BRDFspe.x,BRDFspe.y),BRDFspe.z);
            #endif

            half GrazingTSection = saturate(Reflectivity + smoothness);
            half fre = Pow4(1 - NdotV);

            return lerp(F0,GrazingTSection,fre) * SurReduction;
        }

        half4 frag(Varying i) : SV_Target
        {
            half4 albedo = SAMPLE_TEXTURE2D(_DiffuseTex,sampler_DiffuseTex,i.uv) * _DiffuseColor;
            half4 normal = SAMPLE_TEXTURE2D(_NormalTex,sampler_NormalTex,i.uv);
            half4 metalRough = SAMPLE_TEXTURE2D(_MRTex,sampler_MRTex,i.uv);
            
            float3x3 tbn = {i.tangetWS,i.bitTangetWS,i.normalWS};
            float3 normalTS = UnpackNormalScale(normal,_NormalScale);   //法线数据 颜色空间 > 切线空间 并进行NormalScale变换
            half3 N = NormalizeNormalPerPixel(mul(normalTS,tbn));       //法线 切线空间 > 世界空间 转换

            Light mainLight = GetMainLight();
            half4 lightColor = float4(mainLight.color,1);
            float3 viewDir = normalize(i.viewDirWS);
            float3 normalDir = normalize(N);
            float3 lightDir = mainLight.direction;
            float3 halfDir = normalize(lightDir + viewDir);

            //BRDF
            half metallic = _Metallic * metalRough.r;
            half smoothness = _Roughness * metalRough.a;
            half roughness = pow(1 - smoothness,2);
            
            float nl = max(saturate(dot(normalDir,lightDir)),0.01);
            float nv = max(saturate(dot(normalDir,viewDir)),0.01);
            float nh = max(saturate(dot(normalDir,halfDir)),0.01);
            float hl = max(saturate(dot(halfDir,lightDir)),0.01);

            half NdotH = max(saturate(dot(normalDir,halfDir)),0.01);
            
            half D = Distribution(roughness,normalDir,halfDir);
            half G = Geometry(roughness,normalDir,viewDir,lightDir);
            half3 F0 = lerp(0.04,albedo.rgb, metallic);
            half3 F = FresnelEquation(F0,lightDir,halfDir);
            
            float3 ks = F;
            float3 kd = (1-ks) * (1-metallic);
            half3 BRDF = (D * G * F)/(4 * nl*nv);

            half3 DirectSpeColor = BRDF * lightColor.rgb * nl * PI * albedo;
            
            float3 DirectDiffColor = kd * albedo.rgb * lightColor.rgb * nl;
            float3 DirectResult = DirectSpeColor + DirectDiffColor;

            //Enviroment
                //SH
            half3 shColor = SH_IndirectionDiffuse(normalDir);
            half3 indirect_ks = IndirF_Fuction(nv,F0,roughness);
            half3 indirect_kd = (1 - indirect_ks) * (1 - metallic);
            half3 indirectDiffColor = shColor * indirect_kd * albedo;
                //Reflect
            half3 IndirectSpeCubeColor = IndirectSpeCube(normalDir,viewDir,roughness,1);
            half3 IndirectSpeCubeFactor = IndirectSpeFactor(roughness,smoothness,DirectSpeColor,F0,nv);
            half3 IndirectSpeColor = IndirectSpeCubeColor * IndirectSpeCubeFactor;
            half3 IndirectColor = IndirectSpeColor + indirectDiffColor;

            half3 ResultColor = DirectResult + IndirectColor;

            return float4(ResultColor,1);
            //return float4(ResultColor,1);
        }
        
        ENDHLSL
        }
        
    }
}
























