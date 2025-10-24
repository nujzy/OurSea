#ifndef PBR_FUNCTIONS_INCLUDED
#define PBR_FUNCTIONS_INCLUDED

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #pragma multi_compile _MAIN_LIGHT_SHADOWS
    #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE
    #pragma multi_compile _SHADOWS_SOFT

    //法线分布函数GGX Normal Distribution Fuction
    float Distribution(float roughness,float nh)
    {
        float lerpSquareRoughness = pow(lerp(0.01,1,roughness),2);
        float D = lerpSquareRoughness / (pow(pow(nh,2) * (lerpSquareRoughness - 1) + 1, 2) * PI);
        return D;
    }

    //直接光照 G项子项
    inline real G_subSection(half dot,half k)
    {
        return dot/lerp(dot,1,k);
    }

    //计算G
    float Geometry(float roughness, float nl, float nv)
    {
        //直接光
        //half k = pow(roughness + 1,2) / 8.0;

        //间接光
        //const float d = 1.0 / 8.0;
        //half k = pow(roughness,2) / d;
        
        half k = pow(1 + roughness,2) * 0.5;

        float GLeft = G_subSection(nl,k);
        float GRight = G_subSection(nv,k);
        float G = GLeft * GRight;

        return G;
    }

    //F函数 菲涅耳
    float3 FresnelEquation(float3 F0,float lh)
    {
        float3 F = F0 + (1 - F0) * exp2((-5.55473 * lh - 6.98316) * lh);
        return F;
    }

    //球协光照
    float3 SH_IndirectionDiff(float3 normalWS)
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

    //间接光计算
    float3 IndirF_Fuction(float NdotV, float3 F0, float roughness)
    {
        float Fre = exp2((-5.55473 * NdotV - 6.98316) * NdotV);
        return F0 + Fre * saturate(1 - roughness - F0);
    }

    //间接光 反射探针
    real3 IndirectSpeCube(float3 normalWS,float3 viewWS,float roughness,float AO)
    {
        float3 reflectDirWS = reflect(-viewWS,normalWS);
        roughness = roughness * (1.7 - 0.7 * roughness);
        float MidLevel = roughness * 6;
        float4 speColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0,reflectDirWS, MidLevel);

        #if !defined(UNITY_USE_NATIVE_HDR)

        //用DecodeHDREnvironment将颜色从HDR编码下解码。可以看到采样出的rgbm是一个4通道的值，
        //最后一个m存的是一个参数，解码时将前三个通道表示的颜色乘上xM^y，x和y都是由环境贴图定义的系数，
        //存储在unity_SpecCube0_HDR这个结构中
        return DecodeHDREnvironment(speColor,unity_SpecCube0_HDR) * AO;
        
        #endif

        return speColor.xyz * AO;
    }

    real3 IndirectSpeFactor(half roughness, half smoothness, half3 BRDFspe, half3 F0, half NdotV)
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

    half3 PBR(float3 view, float3 normal, float3 position, float3 albedo, float rough, float metal, float ao, float3 emissive)
    {
        half4 shadowCoord = TransformWorldToShadowCoord(position);
        
        Light mainLight = GetMainLight(shadowCoord);
        half atten = mainLight.shadowAttenuation * mainLight.shadowAttenuation;
        half4 lightColor = float4(mainLight.color,1);

        
        //Roughness Metallic
        float3 halfDir = normalize(view + mainLight.direction);
        float3 lightDir = normalize(mainLight.direction);
        float3 viewDir = normalize(view);
        float nh = max(saturate(dot(normal,halfDir)),0.0001);
        float nl = max(saturate(dot(normal,lightDir)),0.0001);
        float nv = max(saturate(dot(normal,viewDir)),0.0001);
        float vh = max(saturate(dot(viewDir,halfDir)),0.0001);

        half metallic = metal;
        half smoothness = rough;
        half roughness = pow(1 - rough,2);
            
        half D = Distribution(roughness,nh);
        half G = Geometry(roughness,nl,nv);
            
        float hl = max(saturate(dot(halfDir,lightDir)),0.0001);
        float3 F0 = lerp(0.04,albedo.rgb,metallic);
        half3 F = FresnelEquation(F0,hl);

        half3 DirectSpecular = (D * G * F) / (nv * nl * 4);

        //Diffuse
        half3 ks = F;
        half3 kd = (1 - ks) * (1 - metallic);
        half3 DirectDiffColor = kd * nl * lightColor * albedo * atten;
        DirectDiffColor += emissive;
        float3 DirectLightColor = DirectDiffColor + DirectSpecular;
            

        //间接光照
        half3 shcolor = SH_IndirectionDiff(normal) * ao;
        half3 indirect_ks = IndirF_Fuction(nv,F0,roughness);
        half3 indirect_kd = (1 - indirect_ks) * (1 - metallic);
        half3 indirectDiffColor = shcolor * indirect_kd * albedo;

        half3 IndirectSpeCubeColor = IndirectSpeCube(normal,viewDir,roughness,ao);
        half3 IndirectSpeCubeFactor = IndirectSpeFactor(roughness,smoothness,DirectSpecular,F0,nv);
        half3 IndirectSpeColor = IndirectSpeCubeColor * IndirectSpeCubeFactor;

        float3 IndirectColor = IndirectSpeColor + indirectDiffColor;
        return  DirectLightColor + IndirectColor;
    }

    half3 PBRDirectLightResult(Light light, float3 view,float3 normal, float3 albedo, float rough, float metal)
    {
        half4 lightColor = float4(light.color,1);                                 // 获取光照颜色
        float3 viewDir   = normalize(view);
        float3 normalDir = normalize(normal);
        float3 lightDir  = normalize(light.direction);                            // 获取光照颜色
        float3 halfDir   = normalize(viewDir + lightDir);

        float nh = max(saturate(dot(normalDir, halfDir)), 0.001);
        float nl = max(saturate(dot(normalDir, lightDir)),0.001);
        float nv = max(saturate(dot(normalDir, viewDir)),0.01);
        float vh = max(saturate(dot(viewDir, halfDir)),0.0001);
        float hl = max(saturate(dot(halfDir, lightDir)), 0.0001);

        half3 F0 = lerp(0.04,albedo.rgb,metal);

        half D = Distribution(rough, nh);
        half G = Geometry(rough,nl,nv);
        half3 F = FresnelEquation(F0,hl);

        half3 ks = F;
        half3 kd = (1- ks) * (1 - metal);                   // 计算kd

        half3 SpecularResult = (D * G * F) / (nv * nl * 4);

        half3 DirectSpeColor = saturate(SpecularResult * lightColor.rgb * nl * PI );
        half3 DirectDiffColor = kd * albedo.rgb * lightColor.rgb * nl;

        half3 directLightResult = DirectDiffColor + DirectSpeColor;
        return directLightResult;
    }


#endif