#include <getopt.h>
#include <errno.h>
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <snappy-c.h>

#define CHUNK_STREAM_ID		0xFF
#define CHUNK_COMPRESSED	0x00
#define CHUNK_UNCOMPRESSED	0x01
#define CHUNK_SKIPPABLE_MASK	0x80

const char * snappy_strerror(int status) {
	if (status == SNAPPY_INVALID_INPUT)
		return "Invalid input";
	else if (status == SNAPPY_BUFFER_TOO_SMALL)
		return "Buffer too small";
	else
		return "Unknown error";
}

int err(int status) {
	fprintf(stderr, "snappy: %s\n", strerror(-status));
	return 1;
}

int snappy_err(int status) {
	fprintf(stderr, "snappy: %s\n", snappy_strerror(status));
	return 1;
}

int read_chunk(int fd, unsigned char *type, char **buf, size_t *size) {
	char hdr[4];
	size_t len;

	if (!type || !size || !buf)
		return -EINVAL;

	*size = 0;
	len = read(fd, hdr, 4);
	if (len != 4)
		return -EIO;

	*type = hdr[0];
	/* TODO: how do I do this better */
	*size = ((hdr[1] & 0xFF) << 16) | ((hdr[2] & 0xFF) << 8) | (hdr[3] & 0xFF);

	if (*size == 0)
		return 0;

	*buf = malloc(*size);
	if (!*buf)
		return -ENOMEM;

	len = read(fd, *buf, *size);
	if (len != *size) {
		free(*buf);
		return -EIO;
	}

	return 0;
}

int write_chunk(int fd, unsigned char type, char *buf, size_t size) {
	char hdr[4];
	size_t len;

	if (type > 0xFF)
		return -EINVAL;

	hdr[0] = type;
	hdr[1] = (size >> 16) & 0xFF;
	hdr[2] = (size >> 8) & 0xFF;
	hdr[3] = size & 0xFF;

	len = write(fd, hdr, 4);
	if (len != 4)
		return -EIO;

	len = write(fd, buf, size);
	if (len != size)
		return -EIO;

	return 0;
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

	write_chunk(1, CHUNK_STREAM_ID, "sNaPpY", 6);
	for (;;) {
		in_len = read(0, in_buf, in_max);
		if (!in_len)
			break;

		out_len = out_max;

		status = snappy_compress(in_buf, in_len, out_buf, &out_len);
		if (status != SNAPPY_OK)
			return snappy_err(status);

		write_chunk(1, CHUNK_COMPRESSED, out_buf, out_len);
	}
	return 0;
}

int do_uncompress(void) {
	char *in_buf, *out_buf;
	size_t in_max, in_len,
		out_max, out_len;
	unsigned char type;
	int status;

	in_max = out_max = 16384;
	in_buf = malloc(in_max);
	out_buf = malloc(out_max);

	status = read_chunk(0, &type, &in_buf, &in_len);
	if (status != 0)
		return err(status);
	if (type != CHUNK_STREAM_ID || in_len != 6 || memcmp(in_buf, "sNaPpY", 6))
		return snappy_err(SNAPPY_INVALID_INPUT);

	for (;;) {
		status = read_chunk(0, &type, &in_buf, &in_len);
		if (status != 0) {
			if (status == -EIO && in_len == 0)
				break;
			else
				return err(status);
		}

		if (type == CHUNK_COMPRESSED) {
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
		} else if (type == CHUNK_UNCOMPRESSED) {
			write(1, in_buf, in_len);
		} else if (type & CHUNK_SKIPPABLE_MASK) {
			continue;
		} else {
			fprintf(stderr, "snappy: Unknown chunk %02hhX\n", type);
			return 1;
		}
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
