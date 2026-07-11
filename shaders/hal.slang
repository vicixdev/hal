module hal;

public struct GPUBufferRef<T> {
  public uint64_t ref;

  public T Get() {
    T* ptr = (T*)this.ref;

    return *ptr;
  }

  public void Set(T value) {
    T* ptr = (T*)this.ref;
    *ptr = value;
  }

  public GPUBufferRef<T> Next() {
    return GPUBufferRef<T>(this.ref + sizeof(T));
  }

  public GPUBufferRef<U> As<U>() {
    return GPUBufferRef<U>(this.ref);
  }
}

// [[vk::location(8)]]
// StructuredBuffer<IOpaqueDescriptor> textures;

// public SamplerState linearSampler;

// public Texture2D<T, sampleCount, format> GetTexture2DAt<
//   T: ITexelElement = vector<float, 4>,
//   int sampleCount = 0,
//   int format = 0,
// >(
//   int index,
// ) {

//   typealias CurrentTexture2D = Texture2D<T, sampleCount, format>;

//   DescriptorHandle<CurrentTexture2D> textureDescriptorHandle =
//     reinterpret<DescriptorHandle<CurrentTexture2D>>(textures[index]);

//   CurrentTexture2D texture = CurrentTexture2D(textureDescriptorHandle);
//   return texture;
// }

[[vk::location(8)]]
StructuredBuffer<uint64_t> textures;

public SamplerState linearSampler;

public Texture2D<T, sampleCount, format> GetTexture2DAt<
  T: ITexelElement = vector<float, 4>,
  int sampleCount = 0,
  int format = 0,
>(
  int index,
) {

  typealias CurrentTexture2D = Texture2D<T, sampleCount, format>;

  CurrentTexture2D texture = reinterpret<CurrentTexture2D>(textures[index]);
  return texture;
}

