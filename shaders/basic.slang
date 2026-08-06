struct Params {
    float*    in_a;
    float*    in_b;
    float*    out;
}

[[vk::constant_id(0)]]
const float MUL_FACTOR = 1.0;

struct Texture2D_Wrap {
    DescriptorHandle<Texture2D> handle;
}

struct Sampler_Wrap {
    DescriptorHandle<SamplerState> handle;
}

[[vk::binding(0, 0)]]
StructuredBuffer<Texture2D_Wrap> texture_2d_heap;
[[vk::binding(0, 1)]]
StructuredBuffer<Sampler_Wrap> sampler_heap;

// StructuredBuffer<DescriptorHandle<Texture2D>> texture_2d_heap;
// StructuredBuffer<DescriptorHandle<SamplerState>> sampler_heap;

[shader("compute")]
[numthreads(8,8,1)]
void computeMain(
    uint3 threadId : SV_DispatchThreadID,
    uniform Params* params,
) {
    uint index = threadId.x;

    // params.out[index] = params.in_a[index] + params.in_b[index] * MUL_FACTOR;
    params.out[index] = params.in_a[index] + params.in_b[index] * MUL_FACTOR * texture_2d_heap[0].handle.Sample(
        sampler_heap[0].handle, float2(0, 0)
    ).x;
    // params.out[index] = params.in_a[index] + params.in_b[index] * MUL_FACTOR * texture_2d_heap[0].Sample(
    //     sampler_heap[0], float2(0, 0)
    // ).x;
}

