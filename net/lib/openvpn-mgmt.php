<?php
class OpenVPNmgmt {
	function __construct($socket) {
	}
	function status_v3() {
		fwrite($this->fd, "status 3\n");
		return self::parse_status_v3($this->fd);
	}
	static function parse_status_v3($fd) {
		$clients = array();
		$routes = array();
		
		while (($line = fgets($fh)) !== false) {
			$line = explode("\t", $line);
			switch ($line[0]) {
			case "CLIENT_LIST":
				$clients[] = (object) array(
					"user" => $line[1] == "UNDEF" ?
							null : $line[1],
					"addr" => $line[2],
					"vaddr" => $line[3],
				);
				break;
			case "ROUTING_TABLE":
				$routes[] = (object) array(
					"addr" => $line[1],
					"user" => $line[2],
					"nexthop" => $line[3],
				);
				break;
			}
		}
		return array($clients, $routes);
	}
}
