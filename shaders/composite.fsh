#version 120
#include "headers/constants.glsl"
#include "headers/lightmap.glsl"
#include "headers/shadow.glsl"

/*
    Composite Fragment Shader
    The composite programs are fullscreen passes that run after all the gbuffers programs have finished executing.
*/

float AmbientOcclusion(){
    
    const float radius = 0.5;
    const float bias = 0.025;

    vec3 kernel[kernel_size];

    for(int i = 0; i<kernel_size ; i++){
        kernel[i] = vec3(
            randF() * 2.0 - 1.0,
            randF() * 2.0 - 1.0,
            randF()
        );

        kernel[i] = normalize(kernel[i]);
        kernel[i] *= randF();
        float scale = float(i) / float(kernel_size);
        scale = lerp(0.1f, 1.0f, scale * scale);
        kernel[i] *= scale;
    }

    vec3 noise[noise_resolution];

    for(int i = 0; i<noise_resolution; i++){
        noise[i] = vec3(
            randF()*2.0 - 1.0,
            randF()*2.0 - 1.0,
            0.0f
        );

    }

    vec3 normal = normalize( texture2D( colortex1, tex_coords ).rgb * 2.0 - 1.0) ;

    normal = tbn * normal;

    vec2 NoiseScale = vec2(viewWidth/noiseTextureResolution, viewHeight/noiseTextureResolution);
    
    vec3 origin = vec3(tex_coords, texture2D(depthtex0, tex_coords)) * 2.0 - 1.0;
    vec4 intermediary = gbufferProjectionInverse*vec4(origin, 1.0);
    origin = intermediary.xyz/intermediary.w;

    
    float ao = 0.0;

    int noiseX = int(gl_FragCoord.x - 0.5) % int(sqrt(noise_resolution));
    int noiseY = int(gl_FragCoord.y - 0.5) % int(sqrt(noise_resolution));
    float dither = texture2D(noisetex, tex_coords * vec2(viewWidth, viewHeight) / 128.0).b;
    float ditherAnimate = 1.61803398875 * mod(float(frameCounter), 3600.0);
    dither = fract(dither+ditherAnimate);

    vec3 RandomVector = noise[noiseX + (noiseY*4)];
    // vec3 tangent = normalize(RandomVector - normal * dot(RandomVector, normal));
    // vec3 bitangent = cross(normal, tangent);
    // mat3 tbn_new = mat3(tangent, bitangent, normal);
        
    for(int i = 0; i<kernel_size; i++){
        
        vec3 samplePos = tbn*kernel[i];
        samplePos = radius*samplePos + origin;

        vec4 offset = vec4(samplePos, 1.0);
        offset = gbufferProjection * offset;
        offset.xyz /= offset.w;
        offset.xyz = offset.xyz * 0.5 + 0.5;
        
        float thisDepth = texture2D(depthtex0, offset.xy, 0).z;

        float linear = linearizeDepthFast(thisDepth, near, far);

        float rangeCheck = smoothstep(0.0, 1.0, radius / abs(origin.z - linear));
        
        ao += (linear >= samplePos.z + bias ? 1.0 : 0.0) * rangeCheck ;
         
    }

    ao = (ao / kernel_size);
    //ao = pow(ao, 0.4);

    return ao;
}

float get_linear_depth(float depth) {
    return (2.0 * near) / (far + near - depth * (far-near));
}

vec2 OffsetDist(float x, int s) {
        float n = fract(x * 1.414) * 3.1415;
        return (vec2(cos(n), sin(n)) * x / s) *(vec2(cos(n), sin(n)) * x / s);
    }

float AO(){
    float z0 = texture2D(depthtex0, tex_coords, 0).r;
    float linearZ0 = get_linear_depth(z0);
    float dither = texture2D(noisetex, tex_coords * vec2(viewWidth, viewHeight) / 128.0).b;
    float ditherAnimate = 1.61803398875 * mod(float(frameCounter), 3600.0);
    dither = fract(dither + ditherAnimate);

    if (z0 < 0.56) return 1.0;
        float ao = 0.0;

        int samples = 12;
        float scm = 0.6;

        float sampleDepth = 0.0, angle = 0.0, dist = 0.0;
        float fovScale = gbufferProjection[1][1];
        float distScale = max((far-near) * linearZ0 + near, 3.0);
        vec2 scale = vec2(scm / aspectRatio, scm) * fovScale / distScale;

        for (int i = 1; i <= samples; i++) {
            vec2 offset = OffsetDist(i + dither, samples) * scale;
            if (mod(i,2)==0) 
            {
                offset.y = -offset.y;
            }

            vec2 coord1 = tex_coords + offset;
            vec2 coord2 = tex_coords - offset;

            sampleDepth = get_linear_depth(texture2D(depthtex0, coord1).r);
            float aosample = (far-near) * (linearZ0 - sampleDepth) * 2.0;
            angle = clamp(0.5 - aosample, 0.0, 1.0);
            dist = clamp(0.5 * aosample - 1.0, 0.0, 1.0);

            sampleDepth = get_linear_depth(texture2D(depthtex0, coord2).r);
            aosample = (far-near) * (linearZ0 - sampleDepth) * 2.0;
            angle += clamp(0.5 - aosample, 0.0, 1.0);
            dist += clamp(0.5 * aosample - 1.0, 0.0, 1.0);
            
            ao += clamp(angle + dist, 0.0, 1.0);
        }
        ao /= samples;
        
        

        return pow(ao, SSAO_IM);

}

void
main()
{
    /* Account for gamma correction */
    vec3 albedo = pow( texture2D( colortex0, tex_coords ).rgb, vec3( gamma_correction ) );
    vec3 color_nonalbedo = texture2D(colortex0, tex_coords).rgb;
    /* Depth check for sky */
    float depth = texture2D( depthtex0, tex_coords ).z;
    if( depth == 1.0 ) {
        gl_FragData[0] = vec4( albedo, 1.0 );
        return;
    }

    /* Get the normal */
    vec3 normal = normalize( texture2D( colortex1, tex_coords ).rgb * 2.0 - 1.0 );

    /* Get lightmap and it's color */
    vec2 lightmap = texture2D( colortex2, tex_coords ).rg;
    vec3 lightmap_color = get_lightmap_color( lightmap );

    /* Compute cos theta between the normal and sun directions */
    float NdotL = max( dot( normal, normalize( sunPosition ) ), 0.0 );
    
    float ao = AmbientOcclusion();
    
    vec3 ambient = vec3(ambient_gamma * color_nonalbedo * ao);

    if( worldTime > 13050 ){

        vec3 diffuse;
        
        float NdotL = max( dot( normal, normalize( moonPosition ) ), 0.0 );

        diffuse = albedo * (ambient + lightmap_color*2);
        
        /* DRAWBUFFERS:0 */
        gl_FragData[0] = vec4( diffuse, 1.0);

        return;
    }
 
    /* Final diffuse color */

    
    vec3 diffuse = albedo * ( lightmap_color*1.35 + NdotL * get_shadow( depth ) + ambient_gamma )  ;
    
    /* DRAWBUFFERS:0 */
    
    gl_FragData[0] = vec4( diffuse, 1.0 );
  
}