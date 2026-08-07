struct Params {
    float*    in_a;
    float*    in_b;
    float*    out;
}

[[vk::push_constant]]
Params params;

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(
    uint3 threadId : SV_DispatchThreadID,
) {
    uint index = threadId.x;

    params.out[index] = params.in_a[index] + params.in_b[index];
}

