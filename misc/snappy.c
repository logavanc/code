#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <snappy-c.h>

int do_compress(void) {
	char *in_buf, *out_buf;
	size_t in_max, in_len,
		out_max, out_len;
	int status;

	in_max = 16384;
	out_max = snappy_max_compressed_length(in_max);
	in_buf = malloc(in_max);
	out_buf = malloc(out_max);

	for (;;) {
		in_len = read(0, in_buf, in_max);
		if (!in_len)
			break;

		out_len = out_max;

		status = snappy_compress(in_buf, in_len, out_buf, &out_len);
		if (status != SNAPPY_OK)
			abort();

		write(1, out_buf, out_len);
	}
	return 0;
}

int do_uncompress(void) {
	char *in_buf, *out_buf;
	size_t in_max, in_len,
		out_max, out_len;
	int status;

	in_max = out_max = 16384;
	in_buf = malloc(in_max);
	out_buf = malloc(out_max);

	for (;;) {
		in_len = read(0, in_buf, in_max);
		if (!in_len)
			break;

		status = snappy_uncompressed_length(in_buf, in_len, &out_len);
		if (status != SNAPPY_OK)
			abort();

		if (out_len > out_max) {
			free(out_buf);
			out_max = out_len;
			out_buf = malloc(out_max);
		}

		status = snappy_uncompress(in_buf, in_len, out_buf, &out_len);
		if (status != SNAPPY_OK)
			abort();

		write(1, out_buf, out_len);
	}
	return 0;
}

int main(int argc, char *argv[]) {
	if (argc >= 2 && !strcmp(argv[1], "-d"))
		return do_uncompress();
	else
		return do_compress();
}
