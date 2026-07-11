import hal;

StructuredBuffer<float> buffer0;
StructuredBuffer<float> buffer1;
RWStructuredBuffer<float> result;

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 threadId : SV_DispatchThreadID) {
  uint index = threadId.x;

  Texture2D texture = GetTexture2DAt(0);
  float4 s = texture.Sample(linearSampler, float2(0, 0));

  result[index] = buffer0[index] + buffer1[index] + s.x;
}

