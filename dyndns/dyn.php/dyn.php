<?php
// requires at least PHP 5.2 (because JSON)

// TODO: move this file somewhere else where it cannot be read by the web server
define('PERSISTENCE_FILE', (dirname(__FILE__) . DIRECTORY_SEPARATOR . 'dyn.json'));

// dyn:dyn
define('AUTH_USER', 'dyn');
define('AUTH_PW_HASH', 'fHsSpIfQG.AAs');

// ISO
define('DATETIME_FORMAT', '%Y-%m-%d %H:%M:%S');
// d.m.Y
//define('DATETIME_FORMAT', '%d.%m.%Y %H:%M:%S');


define('CONSIDER_FRESH_FOR', 7200);
define('CONSIDER_OFFLINE_AFTER', 3600);


////////////////////////////////////////////////////////////////////////////////

ini_set('display_errors', '0');

// HTTP status codes
$status_messages = array(
	200 => 'OK',
	204 => 'No Content',
	401 => 'Unauthorized',
	403 => 'Forbidden',
	500 => 'Internal Server Error',
);

function quick_response($status, $content_type, $content = NULL, $additional_headers = array()) {
	global $status_messages;

	header("{$_SERVER['SERVER_PROTOCOL']} {$status} {$status_messages[$status]}", TRUE, $status);

	if ("HTTP/1" === substr($_SERVER['SERVER_PROTOCOL'], 0, 6)) {
		header("Connection: close", TRUE);
	}
	if (is_null($content)) {
		$content = $status_messages[$status];
		$content_type = 'text/plain';
	}

	header("Content-Type: {$content_type}");
	foreach ($additional_headers as $hdr) {
		header($hdr, TRUE);
	}

	echo ($content . PHP_EOL);
	exit;
}

function check_auth() {
	if (AUTH_USER !== $_SERVER['PHP_AUTH_USER']) {
		return FALSE;
	}

	if (function_exists('password_verify')) {
		return password_verify($_SERVER['PHP_AUTH_PW'], AUTH_PW_HASH);
	} else {
		// fallback for PHP < 5.5
		$hash = crypt($_SERVER['PHP_AUTH_PW'], AUTH_PW_HASH);
		return (AUTH_PW_HASH === $hash);
	}

}

function format_out_date($date, $styling = NULL) {
	$s = strftime(DATETIME_FORMAT, $date);

	switch ($styling) {
		case 'fresh':
			if (0 < CONSIDER_FRESH_FOR && (time() - $date) < CONSIDER_FRESH_FOR) {
				$s = "<font color=\"green\">{$s}</font>";
			}
			break;
		case 'offline':
			if (0 < CONSIDER_OFFLINE_AFTER && (time() - $date) > CONSIDER_OFFLINE_AFTER) {
				$s = "<font color=\"red\">{$s}</font>";
			}
			break;
	}

	return $s;
}

class Persistence {
	private $path;
	private $fh;
	private $data;

	function __construct($path) {
		$this->path = $path;
		$this->fh = fopen($this->path, 'c+');

		if (FALSE === $this->fh) {
			throw new RuntimeException('failed to open persistence file');
		}

		$tries = 0;
		while (!flock($this->fh, LOCK_EX)) {
			error_log(('flock failed (previous tries: ' . $tries . ')'));
			if (++$tries < 5) {
				sleep(1);
			} else {
				throw new RuntimeException('could not lock persistence file');
			}
		}

		$file_contents = fread($this->fh, filesize($this->path));
		$this->data = json_decode($file_contents, TRUE);
	}

	public function set($client_name, $client_ip) {
		if (!$client_name) { return FALSE; }

		$state = (array_key_exists($client_name, $this->data)
			  ? 'unchanged'
			  : 'new');

		if ('new' === $state) {
			$this->data[$client_name] = array(
				'created_at' => time(),
			);
		}

		if ($this->data[$client_name]['ip'] !== $client_ip) {
			$this->data[$client_name]['ip'] = $client_ip;
			$this->data[$client_name]['last_changed'] = time();
			if ('new' !== $state) { $state = 'updated'; }
		}

		$this->data[$client_name]['last_updated'] = time();

		return array_merge($this->data[$client_name], array(
			'name' => $client_name,
			'state' => $state,
		));
	}

	public function all() {
		return $this->data;
	}

	public function json() {
		return json_encode($this->data);
	}

	function __destruct() {
		ftruncate($this->fh, 0);
		rewind($this->fh);
		fwrite($this->fh, $this->json());
		flock($this->fh, LOCK_UN);
		fclose($this->fh);
	}
}


$persistence = NULL;
try {
	if (!empty($_GET['name']) || isset($_GET['out'])) {
		$persistence = new Persistence(PERSISTENCE_FILE);
	}
} catch (RuntimeException $e) {
	error_log($e->getMessage());
	quick_response(500, 'text/plain;charset=UTF-8', NULL);
}

if (!isset($_GET['out'])) {
	// get client info
	$client_name = (!empty($_GET['name']) ? $_GET['name'] : NULL);
	$client_ip = $_SERVER['REMOTE_ADDR'];

	// update client info
	if (is_null($client_name) || !($changes = $persistence->set($client_name, $client_ip))) {
		$changes = array(
			'ip' => $client_ip,
			'created_at' => time(),
			'state' => 'stateless',
		);
	}

	if (!array_key_exists('quiet', $_GET)) {
		quick_response(200, 'application/json', json_encode($changes));
	} else {
		quick_response(204, 'text/plain;charset=UTF-8', '');
	}
} else {
	if (!check_auth()) {
		$addn_hdrs = array();

		if (!isset($_SERVER['PHP_AUTH_USER'])
			|| !empty($_SERVER['PHP_AUTH_USER'])) {
			// ask user to authenticate
			$addn_hdrs[] = 'WWW-Authenticate: Basic realm="Authenticated Required"';
		}

		quick_response(401, 'text/plain', NULL, $addn_hdrs);
		exit;
	}

	// authenticated => print table of stored IPs
	$all = $persistence->all();

	header('Content-Type: text/html;charset=UTF-8');
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
"http://www.w3.org/TR/html4/loose.dtd">
<html lang="en">
<head>
	<title>dyn.php: Stored IPs</title>
</head>
<body>
	<h1>dyn.php: Stored IPs</h1>
	<table cellpadding="8" border="0">
		<thead>
			<tr>
				<th align="left">Name</th>
				<th align="left">Last IP</th>
				<th>First seen</th>
				<th>Last change</th>
				<th>Last ping</th>
			</tr>
		</thead>
		<tbody>
<?php
if (0 < count($all)):
	foreach ($all as $name => $data):
?>
			<tr>
				<td><?= $name ?></td>
				<td><tt><?= $data['ip'] ?></tt></td>
				<td><?= format_out_date($data['created_at'], 'fresh') ?></td>
				<td><?= format_out_date($data['last_changed'], 'fresh') ?></td>
				<td><?= format_out_date($data['last_updated'], 'offline') ?></td>
			</tr>
<?php
	endforeach;
else:
?>
			<tr><td colspan="5">No stored IPs</td></tr>
<?php
endif;
?>
		</tbody>
	</table>
</body>
</html>
<?php
}
?>
