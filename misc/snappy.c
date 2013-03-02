#include <getopt.h>
#include <errno.h>
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <snappy-c.h>

const char * snappy_strerror(int status) {
	if (status == SNAPPY_INVALID_INPUT)
		return "Invalid input";
	else if (status == SNAPPY_BUFFER_TOO_SMALL)
		return "Buffer too small";
	else
		return "Unknown error";
}

int snappy_err(int status) {
	fprintf(stderr, "snappy: %s\n", snappy_strerror(status));
	return 1;
}

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
			return snappy_err(status);

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
			return snappy_err(status);

		if (out_len > out_max) {
			free(out_buf);
			out_max = out_len;
			out_buf = malloc(out_max);
		}

		status = snappy_uncompress(in_buf, in_len, out_buf, &out_len);
		if (status != SNAPPY_OK)
			return snappy_err(status);

		write(1, out_buf, out_len);
	}
	return 0;
}

int main(int argc, char *argv[]) {
	int opt, compress = 1;

	while ((opt = getopt(argc, argv, "d")) != -1) {
		switch (opt) {
		case 'd':
			compress = 0;
			break;
		}
	}

	if (compress)
		return do_compress();
	else
		return do_uncompress();
}
