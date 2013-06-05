#!/usr/bin/env python
from __future__ import (print_function, unicode_literals)
import base64
import socket
import re

class InvalidPrefixError(Exception):
	pass

class Prefix(object):
	def __init__(self, nick=None, user=None, host=None):
		self.nick = nick
		self.user = user
		self.host = host

	_re_nuh = re.compile(r'^(.+)!([^!@]+)@([^!@]+)$')

	@classmethod
	def parse(cls, prefix):
		# TODO: I seem to remember having seen prefixes in form !server.tld
		self = cls()
		m = cls._re_nuh.match(prefix)
		if m:
			self.nick, self.user, self.host = m.groups()
		elif "." in prefix:
			self.host = prefix
		else:
			self.nick = prefix
		return self

	def unparse(self):
		if not (self.nick is None or self.user is None or self.host is None):
			return self.nick + "!" + self.user + "@" + self.host
		elif self.nick:
			return self.nick
		elif self.host:
			return self.host
		else:
			return None

	def __str__(self):
		if not (self.nick is None or self.user is None or self.host is None):
			return "%s!%s@%s" % (self.nick, self.user, self.host)
		elif self.nick:
			return self.nick
		elif self.host:
			return self.host
		else:
			return "(empty)"

	def __repr__(self):
		return "<IRC.Prefix: %r ! %r @ %r>" % (self.nick, self.user, self.host)

class Line(object):
	"""
	An IRC protocol line.
	"""
	def __init__(self, tags=None, prefix=None, cmd=None, args=None):
		self.tags = tags or {}
		self.prefix = prefix
		self.cmd = cmd
		self.args = args or []

	@classmethod
	def parse(cls, line, parse_prefix=True):
		"""
		Parse an IRC protocol line into a Line object consisting of
		tags, prefix, command, and arguments.
		"""

		line = line.decode("utf-8", "replace")
		line = line.rstrip("\r\n").split(" ")

		i, n = 0, len(line)
		tags = prefix = None
		parv = []
		self = cls()

		while i < n and line[i] == "":
			i += 1

		if i < n and line[i].startswith("@"):
			tags = line[i][1:]
			i += 1
			while i < n and line[i] == "":
				i += 1

		if i < n and line[i].startswith(":"):
			prefix = line[i][1:]
			i += 1
			while i < n and line[i] == "":
				i += 1

		while i < n:
			if line[i].startswith(":"):
				break
			elif line[i] != "":
				parv.append(line[i])
			i += 1

		if i < n:
			trailing = " ".join(line[i:])
			parv.append(trailing[1:])

		if tags:
			self.tags = dict()
			for item in tags.split(";"):
				if "=" in item:
					k, v = item.split("=")
				else:
					k, v = item, true
				self.tags[k] = v

		if prefix:
			if parse_prefix:
				self.prefix = Prefix.parse(prefix)
			else:
				self.prefix = prefix

		if parv:
			self.cmd = parv[0].upper()
			self.args = parv[1:]

		return self

	@classmethod
	def join(cls, argv, strict=True, encode=True):
		i, n = 0, len(argv)

		if i < n and argv[i].startswith("@"):
			if " " in argv[i]:
				raise ValueError("Argument %d contains spaces: %r" % (i, argv[i]))
			i += 1

		if i < n and " " in argv[i]:
			raise ValueError("Argument %d contains spaces: %r" % (i, argv[i]))

		if i < n and argv[i].startswith(":"):
			if " " in argv[i]:
				raise ValueError("Argument %d contains spaces: %r" % (i, argv[i]))
			i += 1

		while i < n-1:
			if not argv[i]:
				raise ValueError("Argument %d is empty: %r" % (i, argv[i]))
			elif argv[i].startswith(":"):
				raise ValueError("Argument %d starts with ':': %r" % (i, argv[i]))
			elif " " in argv[i]:
				raise ValueError("Argument %d contains spaces: %r" % (i, argv[i]))
			i += 1

		parv = argv[:i]

		if i < n:
			if not argv[i] or argv[i].startswith(":") or " " in argv[i]:
				parv.append(":%s" % argv[i])
			else:
				parv.append(argv[i])

		return " ".join(parv)

	def unparse(self):
		parv = []

		if self.tags:
			tags = [k if v is True else k + b"=" + v
				for k, v in self.tags.items()]
			parv.append("@" + b",".join(tags))

		if self.prefix:
			parv.append(":" + self.prefix.unparse())

		parv.append(self.cmd)

		parv.extend(self.args)

		return self.join(parv)

	def __repr__(self):
		return "<IRC.Line: tags=%r prefix=%r cmd=%r args=%r>" % (
						self.tags, self.prefix,
						self.cmd, self.args)

class Connection(object):
	def __init__(self):
		self.host = None
		self.port = None
		self.ai = None
		self._fd = None
		self._file = None

	def connect(self, host, port, ssl=False):
		self.ai = socket.getaddrinfo(host, str(port), 0, socket.SOCK_STREAM)
		print(repr(self.ai))
		for af, proto, _, cname, addr in self.ai:
			self._fd = socket.socket(af, proto)
			self._fd.connect(addr)
			break
		import io
		self._fi = self._fd.makefile("rwb")

	def writeraw(self, buf):
		self._fi.write(buf+b"\r\n")
		self._fi.flush()

	def readraw(self):
		return self._fi.readline()

	def write(self, *args):
		self.writeraw(Line.join(args))

	def read(self):
		return Line.parse(self.readraw())

# vim: ts=4:sw=4
