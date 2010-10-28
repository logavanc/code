<?php
namespace Ident;

/*
 * Ident Ident\query($rhost, $rport, $lhost, $lport)
 *     $rhost, $rport
 *         remote (client) host/port
 *     $lhost, $lport
 *         local (server) host/port
 *
 * Ident Ident\query_stream($stream)
 *     $stream
 *         handle to connected stream resource
 *
 * Ident Ident\query_socket($socket)
 *     $socket
 *         handle to connected socket resource
 *
 * class Ident {
 *      bool $success;
 *      int $lport;
 *      int $rport;
 *      string $rcode;
 *      string $ecode;
 *      string $ostype;
 *      string $charset;
 *      string $userid;
 * }
 */

class Ident {
	static $debug = false;

	static function debug($str) {
		if (self::$debug) print $str;
	}

	public $success;
	public $lport;
	public $rport;
	public $rcode;
	public $ecode;
	public $ostype;
	public $charset;
	public $userid;

	function __construct($str=null) {
		if (!strlen($str))
			return;

		$str = rtrim($str, "\r\n");
		Ident::debug("parsing: $str\n");

		$ports = strtok($str, ":");
		$ports = explode(",", $ports, 2);
		$this->rport = intval($ports[0]);
		$this->lport = intval($ports[1]);

		$this->rcode = strtoupper(trim(strtok(":")));
		switch ($this->rcode) {
		case "ERROR":
			$this->success = false;
			$this->ecode = strtoupper(trim(strtok(null)));
			break;
		case "USERID":
			$this->success = true;
			$ostype = strtok(":");
			if (strpos($ostype, ",") !== false) {
				list ($ostype, $charset) = explode(",", $ostype, 2);
			} else {
				$charset = "US-ASCII";
			}
			$this->ostype = trim($ostype);
			$this->charset = trim($charset);
			$this->userid = ltrim(strtok(null));
			break;
		default:
			$this->success = false;
		}
	}

	function __toString() {
		$str = "";

		if ($this->success)
			$str = "ident: ";
		else
			$str = "error: ";

		switch ($this->rcode) {
		case "ERROR":
			$str .= "server error: [".$this->ecode."] ".strerror($this->ecode);
			break;
		case "USERID":
			$str .= "USERID: {$this->userid} (ostype: {$this->ostype})";
			break;
		default:
			$str .= "{$this->rcode}: {$this->ecode}";
		}
		return $str;
	}
}

function _failure($ecode) {
	$r = new Ident();
	$r->success = false;
	$r->rcode = "X-CLIENT-ERROR";
	$r->ecode = $ecode;
	return $r;
}

function strerror($ecode) {
	switch ($ecode) {
	case "INVALID-PORT":
		return "invalid port specification";
	case "NO-USER":
		return "connection not identifiable";
	case "HIDDEN-USER":
		return "server refused to identify connection";
	case "UNKNOWN-ERROR":
		return "unknown server failure";
	default:
		if ($ecode[0] == "X")
			return "unknown server error code: $ecode";
		else
			return "invalid server error code: $ecode";
	}
}

function escape_host($h) {
	if (strpos($h, ":") !== false)
		return "[$h]";
	else
		return $h;
}
function split_host_port($h) {
	$pos = strrpos($h, ":");
	return array(
		substr($h, 0, $pos),
		intval(substr($h, ++$pos)),
	);
}

function query($rhost, $rport, $lhost, $lport) {
	$timeout = 2;
	$authport = getservbyname("auth", "tcp");

	$lhost_w = escape_host($lhost);
	$rhost_w = escape_host($rhost);

	Ident::debug("query($rhost_w:$rport -> $lhost_w:$lport)\n");

	$ctx = array();
	$ctx["socket"]["bindto"] = "$lhost_w:0";
	$ctx = stream_context_create($ctx);

	$st = @stream_socket_client("tcp://$rhost_w:$authport", $errno, $errstr,
		$timeout, \STREAM_CLIENT_CONNECT, $ctx);

	if (!$st)
		return _failure("[$errno] $errstr");

	fwrite($st, "$rport,$lport\r\n");
	$reply_str = fgets($st, 1024);
	fclose($st);
	return new Ident($reply_str);
}

function query_stream($sh) {
	$local = stream_socket_get_name($sh, false);
	if (!$local) {
		return _failure("unable to determine socket name");
	}
	$remote = stream_socket_get_name($sh, true);
	if (!$remote) {
		return _failure("unable to determine peer name");
	}
	$local = split_host_port($local);
	$remote = split_host_port($remote);
	return query($remote[0], $remote[1], $local[0], $local[1]);
}

function query_socket($sh) {
	if (!socket_getsockname($sh, $lhost, $lport)) {
		$errno = socket_last_error($sh);
		$err = socket_strerror($errno);
		return _failure("unable to determine socket name: [$errno] $err");
	}
	if (!socket_getpeername($sh, $rhost, $rport)) {
		$errno = socket_last_error($sh);
		$err = socket_strerror($errno);
		return _failure("unable to determine peer name: [$errno] $err");
	}
	return query($rhost, $rport, $lhost, $lport);
}

/// TEST FUNCTIONS

function test_sshenv() {
	$s = getenv("SSH_CONNECTION");
	list ($rhost, $rport, $lhost, $lport) = explode(" ", $s);
	var_dump(query($rhost, $rport, $lhost, $lport));
}

function test_stream() {
	$se = stream_socket_server("tcp://[::]:1234");
	if ($co = stream_socket_accept($se, -1)) {
		print "accept\n";
		var_dump($re = query_stream($co));
		fwrite($co, "You are {$re->userid}\n");
		fclose($co);
	}
	fclose($se);
}

function test_socket() {
	$se = socket_create(AF_INET6, SOCK_STREAM, SOL_TCP);
	socket_bind($se, "::", 1234);
	socket_listen($se, 1);
	if ($co = socket_accept($se)) {
		print "accept\n";
		var_dump($re = query_socket($co));
		socket_write($co, "You are {$re->userid}\n");
		socket_close($co);
	}
	socket_close($se);
}

function test_stream_client($host="localhost", $port=22) {
	$host = escape_host($host);
	$co = stream_socket_client("tcp://$host:$port");
	var_dump(query_stream($co));
	fclose($co);
}

function test_socket_client($af=AF_INET, $host="localhost", $port=22) {
	$co = socket_create($af, SOCK_STREAM, SOL_TCP);
	socket_connect($co, $host, $port);
	var_dump(query_socket($co));
	socket_close($co);
}