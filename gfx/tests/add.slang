/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

struct Parameters {
	float*	in_a;
	float*	in_b;
	float*	out;
}

[SpecializationConstant]
const float MULT_FACTOR;

[push_constant]
Parameters* parameters;

[shader("compute")]
[numthreads(128,1,1)]
void add(
	uint3 threadId : SV_DispatchThreadID,
) {
	uint i = threadId.x;

	parameters.out[i] = parameters.in_a[i] + parameters.in_b[i] * MULT_FACTOR;
}

