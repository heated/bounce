//
//  Shaders.metal
//  bounce
//
//  Created by Edward Swernofsky on 11/26/19.
//  Copyright © 2019 Edward Swernofsky. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
// #import "ShaderTypes.h"

using namespace metal;

struct Ball {
    float2 pos;
    float2 vel;
};

struct VertexOut {
    float4 position [[ position ]];
    float point_size [[ point_size ]];
    float4 color;
};

bool isBounded(float x, float max) {
    return 0 <= x && x < max;
}

kernel void moveBalls(device Ball* balls,
                      uint i [[ thread_position_in_grid ]]) {
    balls[i].pos += balls[i].vel;
    
    if (!isBounded(balls[i].pos.x, 800)) {
        balls[i].vel.x *= -1;
    }
    
    if (!isBounded(balls[i].pos.y, 600)) {
        balls[i].vel.y *= -1;
    }
}

vertex VertexOut vertexShader(const device float2* vertices,
                              const device float4* colors,
                              uint i [[ vertex_id ]]) {
    VertexOut out;
    out.position = float4(vertices[i], 0, 1);
    out.color = colors[i];
    out.point_size = 8;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[ stage_in ]],
                               float2 pos [[ point_coord ]],
                               texture2d<float> circle [[ texture(0) ]]) {
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    float4 sample = circle.sample(colorSampler, pos) * in.color;

    return float4(sample);
}
