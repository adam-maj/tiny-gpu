module splitter144 (
	input wire [35:0] in0,
	input wire [35:0] in1,
	input wire [35:0] in2,
	input wire [35:0] in3,

	output wire [3:0] out0,
	output wire [31:0] out1,
	output wire [3:0] out2,
	output wire [31:0] out3,
	output wire [31:0] out4,
	output wire [7:0] out5,
	output wire [31:0] out6
);
	// Input field layout (low -> high): (1, 8, 1, 8, 8, 2, 8) = 36 bits
	// Output fields are bit-interleaved across in0..in3, producing:
	// (4, 32, 4, 32, 32, 8, 32)

	// out0: field0 (1 bit) => 4 bits
	assign out0 = {in3[0], in2[0], in1[0], in0[0]};

	// out1: field1 (8 bits, in[*][8:1]) => 32 bits, interleaved by bit index
	assign out1 = {
		{in3[8], in2[8], in1[8], in0[8]},
		{in3[7], in2[7], in1[7], in0[7]},
		{in3[6], in2[6], in1[6], in0[6]},
		{in3[5], in2[5], in1[5], in0[5]},
		{in3[4], in2[4], in1[4], in0[4]},
		{in3[3], in2[3], in1[3], in0[3]},
		{in3[2], in2[2], in1[2], in0[2]},
		{in3[1], in2[1], in1[1], in0[1]}
	};

	// out2: field2 (1 bit, in[*][9]) => 4 bits
	assign out2 = {in3[9], in2[9], in1[9], in0[9]};

	// out3: field3 (8 bits, in[*][17:10]) => 32 bits
	assign out3 = {
		{in3[17], in2[17], in1[17], in0[17]},
		{in3[16], in2[16], in1[16], in0[16]},
		{in3[15], in2[15], in1[15], in0[15]},
		{in3[14], in2[14], in1[14], in0[14]},
		{in3[13], in2[13], in1[13], in0[13]},
		{in3[12], in2[12], in1[12], in0[12]},
		{in3[11], in2[11], in1[11], in0[11]},
		{in3[10], in2[10], in1[10], in0[10]}
	};

	// out4: field4 (8 bits, in[*][25:18]) => 32 bits
	assign out4 = {
		{in3[25], in2[25], in1[25], in0[25]},
		{in3[24], in2[24], in1[24], in0[24]},
		{in3[23], in2[23], in1[23], in0[23]},
		{in3[22], in2[22], in1[22], in0[22]},
		{in3[21], in2[21], in1[21], in0[21]},
		{in3[20], in2[20], in1[20], in0[20]},
		{in3[19], in2[19], in1[19], in0[19]},
		{in3[18], in2[18], in1[18], in0[18]}
	};

	// out5: field5 (2 bits, in[*][27:26]) => 8 bits
	assign out5 = {
		{in3[27], in2[27], in1[27], in0[27]},
		{in3[26], in2[26], in1[26], in0[26]}
	};

	// out6: field6 (8 bits, in[*][35:28]) => 32 bits
	assign out6 = {
		{in3[35], in2[35], in1[35], in0[35]},
		{in3[34], in2[34], in1[34], in0[34]},
		{in3[33], in2[33], in1[33], in0[33]},
		{in3[32], in2[32], in1[32], in0[32]},
		{in3[31], in2[31], in1[31], in0[31]},
		{in3[30], in2[30], in1[30], in0[30]},
		{in3[29], in2[29], in1[29], in0[29]},
		{in3[28], in2[28], in1[28], in0[28]}
	};
endmodule

