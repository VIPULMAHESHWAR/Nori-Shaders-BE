// __multiversion__

#include "fragmentVersionCentroid.h"

#if __VERSION__ >= 300
	#ifndef BYPASS_PIXEL_SHADER
		_centroid in highp vec2 uv0;
		_centroid in highp vec2 uv1;
	#endif
#else
	#ifndef BYPASS_PIXEL_SHADER
		varying highp vec2 uv0;
		varying highp vec2 uv1;
	#endif
#endif

varying vec4 vcolor;

#ifdef FOG
	varying float fogalpha;
#endif

#include "uniformShaderConstants.h"
#include "uniformPerFrameConstants.h"

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;
LAYOUT_BINDING(1) uniform sampler2D TEXTURE_1;
LAYOUT_BINDING(2) uniform sampler2D TEXTURE_2;

precision highp float;

varying vec3 chunkedpos;
varying vec3 worldpos;
varying vec3 sunPos;

#include "common.glsl"

vec2 calcpcoord(vec2 viewvec, vec2 ppos, mat2 texcoord){
	vec2 pcoordn = texcoord[1].xy;
	if(dot(textureLod(TEXTURE_0, pcoordn, 0.0).rgb, vec3(1.0, 1.0, 1.0)) > 0.0){

	#if defined(ENABLE_PARALLAX) && !defined(ALPHA_TEST)
		vec2 spcoord = vec2(0.0, 0.0);
		for(int i = 0; i < PARALLAX_STEP && texture2D(TEXTURE_0, pcoordn).a < 1.0 - float(i) / PARALLAX_RES; ++i){
			spcoord += viewvec * PARALLAX_DEPTH;
			pcoordn += viewvec * (PARALLAX_DEPTH / PARALLAX_RES);
		}
		vec2 pcoord = texcoord[0].xy - fract(ppos) * 0.015625 + fract(ppos + spcoord) * 0.015625;
		return pcoord;
	#endif

	} else {
		return texcoord[0].xy;
	}
}

float calcpshadow(vec3 lightpos, vec2 ptcoord){
	float totallight = 1.0;

	#if defined(ENABLE_PARALLAX_SHADOW) && defined(ENABLE_PARALLAX) && !defined(ALPHA_TEST)
	float originsample = texture2D(TEXTURE_0, ptcoord).a;
	for(int i = 0; i < PSHADOW_STEP; i++){
		ptcoord += lightpos.xy * PSHADOW_OFFSET;
		if(texture2D(TEXTURE_0, ptcoord).a - float(i) / PARALLAX_RES > originsample) totallight *= 0.2;
	}
	#endif

	return totallight;
}

vec3 getTangent(vec3 normal){
	vec3 tangent = vec3(0, 0, 0);
	if(normal.x > 0.0){ tangent = vec3(0, 0, -1);
	} else if(normal.x < -0.5){ tangent = vec3(0, 0, 1);

	} else if(normal.y > 0.0){ tangent = vec3(1, 0, 0);
	} else if(normal.y < -0.5){ tangent = vec3(1, 0, 0);

	} else if(normal.z > 0.0){ tangent = vec3(1, 0, 0);
	} else if(normal.z < -0.5){ tangent = vec3(-1, 0, 0);
	}
	return tangent;
}

float ditributionGGX(float NdotH, float roughness){
	float roughSquared = sqr4x(roughness);
	float d = (NdotH * roughSquared - NdotH) * NdotH + 1.0;
	return roughSquared / (pi * d * d);
}

float geometrySchlick(float NdotV, float NdotL, float roughness){
	float k = sqr2x(roughness) * 0.5;
	float view = NdotV * (1.0 - k) + k;
	float light = NdotL * (1.0 - k) + k;
	return 0.25 / (view * light);
}

void main()
{
#ifdef BYPASS_PIXEL_SHADER
	gl_FragColor = vec4(0, 0, 0, 0);
	return;
#else

	vec3 normal = normalize(cross(dFdx(chunkedpos.xyz), dFdy(chunkedpos.xyz)));
	vec3 tangent = getTangent(normal);
	vec3 binormal = normalize(cross(tangent, normal));
	mat3 tbnMatrix = transpose(mat3(tangent, binormal, normal));

	vec3 viewvec = normalize(tbnMatrix * worldpos);
	vec3 ppos = tbnMatrix * chunkedpos;

	vec2 topleftmUV = fract(uv0 * 32.0) * 0.015625;
	vec2 albedoUv = uv0 - topleftmUV;
	vec2 merUv = uv0 - (topleftmUV - vec2(0.015625, 0.0));
	vec2 normaltUv = uv0 - (topleftmUV - vec2(0.0, 0.015625));

	vec3 smat = vec3(0, 0, 0);
	vec4 mertex = textureLod(TEXTURE_0, calcpcoord(viewvec.xy, ppos.xy, mat2(merUv, normaltUv)), 0.0);
	if((mertex.r > 0.0 || mertex.g > 0.0 || mertex.b > 0.0) && mertex.a > 0.0) smat = mertex.rgb;
	float metallic = saturate(smat.g);
	float emission = saturate(smat.b);
	float roughness = saturate(pow(1.0 - smat.r, 2.0));
	float ssmooth = saturate(1.0 - roughness * 3.0);

	vec3 rawNormal = textureGrad(TEXTURE_0, calcpcoord(viewvec.xy, ppos.xy, mat2(normaltUv, normaltUv)), dFdx(uv0 * ADJUST_MIPMAP), dFdy(uv0 * ADJUST_MIPMAP)).rgb;
	if(rawNormal.r > 0.0 || rawNormal.g > 0.0 || rawNormal.b > 0.0){
		normal = rawNormal * 2.0 - 1.0;
		normal.rg *= max0(1.0 - wrain * 0.5);
		normal.rgb = normalize(normal * tbnMatrix);
	}

	vec3 lightpos = normalize(vec3(cos(SUN_LIGHT_ANGLE), sin(SUN_LIGHT_ANGLE), 0.0));
	vec3 upPosition = vec3(0.0, 1.0, 0.0);
	vec3 viewDir = normalize(-worldpos);
	vec3 halfDir = normalize(viewDir + lightpos);

	float NdotL = max0(dot(normal, lightpos)); // diffuse lighting / bump map
	float NdotU = max0(dot(normal, upPosition));
	float NdotH = max(0.001, dot(normal, halfDir)); // specular lighting ( blinn phong model )
	float NdotV = max(0.001, dot(normal, viewDir));

	vec4 albedo = textureGrad(TEXTURE_0, calcpcoord(viewvec.xy, ppos.xy, mat2(albedoUv, normaltUv)), dFdx(uv0 * ADJUST_MIPMAP), dFdy(uv0 * ADJUST_MIPMAP));

	#ifdef SEASONS_FAR
		albedo.a = 1.0;
	#endif

	#ifdef ALPHA_TEST
		#ifdef ALPHA_TO_COVERAGE
			#define ALPHA_THRESHOLD 0.05
		#else
			#define ALPHA_THRESHOLD 0.5
		#endif
		if(albedo.a < ALPHA_THRESHOLD) discard;
	#endif

	#ifndef SEASONS
		#if !defined(ALPHA_TEST) && !defined(BLEND)
			albedo.a = vcolor.a;
		#endif

		albedo.rgb *= vcolor.g > vcolor.r ? normalize(vcolor.rgb) * sqrt(length(vcolor.rgb)) : sqrt(vcolor.rgb);
	#else
		albedo.rgb *= mix(vec3(1.0,1.0,1.0), texture2D(TEXTURE_2, vcolor.rg).rgb * 2.0, vcolor.b);
		albedo.rgb *= vcolor.aaa;
		albedo.a = 1.0;
	#endif

		albedo.rgb = toLinear(albedo.rgb);

	vec3 albedonoem = albedo.rgb;
	vec3 ambientColor = vec3(0.3, 0.3, 0.3) * saturate(1.0 - wrain * 0.3 + fnight * 0.6);
		ambientColor *= uv1.y;

	float bvalue = smoothstep(texture2D(TEXTURE_1, vec2(0, 1)).r * uv1.y, 1.0, uv1.x);
	float blocklights = mix(mix(0.0, uv1.x, bvalue), uv1.x, wrain);
		blocklights = blocklights * (NdotU * 0.5 + 0.5);
		ambientColor += vec3(1.0, 0.5, 0.2) * blocklights + pow(blocklights * 1.15, 5.0);

	vec2 dispcoord = calcpcoord(viewvec.xy, ppos.xy, mat2(normaltUv, normaltUv));
	float pselfshadow = calcpshadow(tbnMatrix * lightpos, dispcoord);
		pselfshadow *= NdotL;

	vec3 diffuseColor = vec3(FOG_COLOR.r * max0(1.0 - fnight * 0.4), FOG_COLOR.g * max0(0.9 - fnight * 0.1), FOG_COLOR.b * (0.8 + fnight * 0.2)) * 3.0;
	float outdoor = smoothstep(0.845, 0.87, uv1.y);
		ambientColor += diffuseColor * pselfshadow * outdoor * (1.0 - wrain);
		albedo.rgb = albedo.rgb * ambientColor;
		albedo.rgb += emission * albedonoem * 5.0;

	float atten = max0(1.0 - roughness) * geometrySchlick(NdotV, NdotL, roughness) * ditributionGGX(NdotH, roughness);
		albedo += atten * pselfshadow * vec4(FOG_COLOR.r * 2.0, FOG_COLOR.g * 1.8, FOG_COLOR.b * 1.6, 1.0) * outdoor * (1.0 - wrain);

	#ifdef ENABLE_REFLECTION
	vec3 reflectedvector = reflect(normalize(worldpos), normal);
	vec3 skyReflection = renderSkyColor(reflectedvector, upPosition, 1.5);
	float cloudF = smoothstep(1.0, 0.95, length(nworldpos.xz)) * float(dot(reflectedvector, upPosition) > 0.0);

		reflectedvector /= reflectedvector.y;

	vec4 cloudReflection = calcCloudColor(reflectedvector, reflectedvector);
		skyReflection = mix(skyReflection, cloudReflection.rgb, cloudReflection.a * cloudF);
		skyReflection = mix(skyReflection, skyReflection * albedonoem, metallic);

	vec3 f0 = vec3(0.04);
		f0 = mix(f0, albedonoem, metallic);
 	vec3 fresnel = f0 + (1.0 - f0) * pow(1.0 - NdotV, 5.0);
	 	albedo.rgb= mix(albedo.rgb, albedo.rgb * vec3(0.03), metallic);
	 	albedo = mix(albedo, vec4(skyReflection, 1.0), vec4(fresnel, length(fresnel)) * max(ssmooth, wrain * normal.y) * outdoor);
	#endif

	vec3 newfogcolor = renderSkyColor(normalize(worldpos), upPosition, 1.0);
		albedo.rgb = mix(albedo.rgb, newfogcolor, max0(length(worldpos) / 100.0) * wrain);
	#ifdef FOG
		albedo.rgb = mix(albedo.rgb, newfogcolor, fogalpha);
	#endif
		albedo.rgb = colorCorrection(albedo.rgb);

	/// debugging section
	#ifdef LOOK_NORMALS
		albedo = vec4(normal, 1.0);
	#endif
	#ifdef LOOK_ATLAS_TERRAIN
		albedo = texture2D(TEXTURE_0, chunkedpos.xz / 8.0);
	#endif
	#ifdef LOOK_METALLIC
		albedo = vec4(metallic);
	#endif
	#ifdef LOOK_EMISSION
		albedo = vec4(emission);
	#endif
	#ifdef LOOK_ROUGHNESS
		albedo = vec4(roughness);
	#endif

	gl_FragColor = albedo;

#endif
}
