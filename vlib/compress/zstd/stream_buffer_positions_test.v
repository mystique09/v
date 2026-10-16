module zstd

fn test_stream_buffers_preserve_offsets_and_update_positions() ! {
	message := 'streaming through small buffers '.repeat(12).bytes()
	mut source := [u8(0xaa)]
	source << message
	mut input := InBuffer{
		src:  source.data
		size: usize(source.len)
		pos:  1
	}
	mut bytes := []u8{len: 7, init: 0xcc}
	mut output := OutBuffer{
		dst:  bytes.data
		size: usize(bytes.len)
		pos:  1
	}
	mut compressor := new_cctx(nb_threads: 0)!
	defer { compressor.free_cctx() }
	mut compressed := []u8{}
	mut complete := false
	for _ in 0 .. 1000 {
		previous := input.pos
		output.pos = 1
		remaining := compressor.compress_stream2(&output, &input, .end)!
		assert input.pos >= previous && input.pos <= input.size
		assert output.pos >= 1 && output.pos <= output.size
		assert bytes[0] == 0xcc
		compressed << bytes[1..int(output.pos)]
		if remaining == 0 {
			complete = true
			break
		}
	}
	assert complete
	assert input.pos == input.size
	assert input.src == source.data && input.size == usize(source.len)
	assert output.dst == bytes.data && output.size == usize(bytes.len)

	mut encoded := [u8(0xbb)]
	encoded << compressed
	input = InBuffer{encoded.data, usize(encoded.len), 1}
	mut decoder := new_dctx()!
	defer { decoder.free_dctx() }
	mut decoded := []u8{}
	complete = false
	for _ in 0 .. 1000 {
		previous := input.pos
		output.pos = 1
		remaining := decoder.decompress_stream(&output, &input)!
		assert input.pos >= previous && input.pos <= input.size
		assert output.pos >= 1 && output.pos <= output.size
		assert bytes[0] == 0xcc
		decoded << bytes[1..int(output.pos)]
		if remaining == 0 {
			complete = true
			break
		}
	}
	assert complete
	assert input.pos == input.size
	assert input.src == encoded.data && input.size == usize(encoded.len)
	assert output.dst == bytes.data && output.size == usize(bytes.len)
	assert decoded == message
}
