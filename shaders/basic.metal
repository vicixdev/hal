#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

struct Params {
	float device* in_a;
	float device* in_b;
	float device* out;
};

[[kernel]]
void computeMain(
	uint3			thread_id	[[thread_position_in_grid]],
	Params constant&	params		[[buffer(0)]]
) {
	uint i = thread_id.x;

	float a = params.in_a[i];
	float b = params.in_b[i];
	params.out[i] = a + b;
}

