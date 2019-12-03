#include <metal_stdlib>
#include <simd/simd.h>
#import "Constants.h"

using namespace metal;

constant float2 renderMax = float2(width, height);

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

float2 renderPos(float2 pos) {
    return 2 * (pos+ballRad) / renderMax - 1;
}

kernel void moveBalls(device Ball* balls,
                      uint i [[ thread_position_in_grid ]]) {
    balls[i].pos += balls[i].vel;
    
    if (!isBounded(balls[i].pos.x, maxX)) {
        balls[i].vel.x *= -1;
    }
    
    if (!isBounded(balls[i].pos.y, maxY)) {
        balls[i].vel.y *= -1;
    }
}

vertex VertexOut vertexShader(const device Ball* balls,
                              const device float4* colors,
                              uint i [[ vertex_id ]]) {
    VertexOut out;
    out.position = float4(renderPos(balls[i].pos), 0, 1);
    out.color = colors[i];
    out.point_size = ballDiam;
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
