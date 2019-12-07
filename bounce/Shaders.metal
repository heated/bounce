#include <metal_stdlib>
#include <simd/simd.h>
#import "Constants.h"

using namespace metal;

uint ceil2(float x) {
    return int(x) + 1 - int(1 + int(x) - x);
}

constant float2 renderMax = float2(width, height);
// look idk man, ceil isn't allowed here
constant uint gridCols = ceil2(maxX / ballDiam);
constant uint gridRows = ceil2(maxY / ballDiam);

struct Ball {
    float2 pos;
    float2 vel;
};

struct Tile {
    float2 balls[tileSlots];
};

struct VertexOut {
    float4 position [[ position ]];
    float point_size [[ point_size ]];
    float4 color;
};

bool isBoundedF(float x, float max) {
    return 0 <= x && x < max;
}

bool isBoundedI(int x, int max) {
    return 0 <= x && x < max;
}

float2 renderPos(float2 pos) {
    return 2 * (pos+ballRad) / renderMax - 1;
}

uint2 gridPos(float2 pos) {
    int2 div = int2(pos / ballDiam);
    uint2 upperBound = uint2(max(div, int2(0, 0)));
    return min(upperBound,
               uint2(gridCols - 1, gridRows - 1));
}

uint gridIdx(float2 pos) {
    uint2 i = gridPos(pos);
    return i.y * gridCols + i.x;
}

kernel void moveBalls(device Ball* balls,
                      device Tile* grid,
                      device atomic_uint* sizes,
                      uint i [[ thread_position_in_grid ]]) {
    balls[i].vel.y -= gravity;
    balls[i].vel *= 1 - friction;
    balls[i].pos += balls[i].vel;
    
    float2 p = balls[i].pos;
    
    if (p.x < 0) balls[i].vel.x += -p.x * wallForce;
    if (p.y < 0) balls[i].vel.y += -p.y * wallForce;
    if (p.x >= maxX) balls[i].vel.x += (maxX-p.x) * wallForce;
    if (p.y >= maxY) balls[i].vel.y += (maxY-p.y) * wallForce;
    
    uint j = gridIdx(balls[i].pos);
    uint8_t k = atomic_fetch_add_explicit(&sizes[j], 1, memory_order_relaxed);
    grid[j].balls[k] = balls[i].pos;
}

kernel void collideBalls(device Ball* balls,
                         const device Tile* grid,
                         const device uint* sizes,
                         uint i [[ thread_position_in_grid ]]) {
    float2 p1 = balls[i].pos;
    int2 j = int2(p1 / ballDiam);
    int x = j.x;
    int y = j.y;
    
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            int nx = x + dx;
            int ny = y + dy;
            if (!isBoundedI(nx, gridCols) ||
                !isBoundedI(ny, gridRows)) {
                continue;
            }
            
            uint k = ny * gridCols + nx;
            for (uint b_i = 0; b_i <= tileSlots && b_i < sizes[k]; ++b_i) {
                float2 p2 = grid[k].balls[b_i];

                if ((p2.x == 0 && p2.y == 0) ||
                    (p1.x == p2.x && p1.y == p2.y)) {
                    continue;
                }
                
                float2 diff = p1 - p2;
                float2 d = diff * diff;
                float dist_2 = d.x + d.y;
                if (dist_2 >= pow(ballDiam, 2)) {
                    continue;
                }
                
                float dist = sqrt(dist_2);
                float acc = (ballDiam - dist) * collForce;
                balls[i].vel += diff * acc;
                balls[i].vel *= 1 - collFriction;
            }
        }
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
