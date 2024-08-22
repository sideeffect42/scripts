# dyn.php

[`dyn.php`](dyn.php) is a tiny (< 250 LoC) CGI script written in PHP which
provides a simple API to manage changes of dynamic IP addresses and which serves
as a "What's my IP address?" tool as well.

## Usage

Install the `dyn.php` to your web server and configure the configuration
variables at the very top to your liking.

> [!IMPORTANT]
> Make sure to change `PERSISTENCE_FILE` and `AUTH_PW_HASH`!


## Configuration

At the very top of the `dyn.php` script there are a handful of `define`s which
serve as configuration options.

<dl>
	<dt><code>PERSISTENCE_FILE</code></dt>
	<dd>the file which the script uses to store its data. This file should now be readable by the web server.</dd>
	<dt><code>AUTH_USER</code></dt>
	<dd>the user name used for authentication to <code>?out</code>.</dd>
	<dt><code>AUTH_PW_HASH</code></dt>
	<dd>a PHP <code>crypt()</code>/<code>password_hash()</code> hashed form of the password used for authentication to <code>?out</code>.</dd>
	<dt><code>DATETIME_FORMAT</code></dt>
	<dd>the output format for dates in <tt>strftime(3)</tt> format.</dd>
	<dt><code>CONSIDER_FRESH_FOR</code></dt>
	<dd>entries will be marked green if a system was added or its IP has changed in the last N seconds. Set to 0 to disable.</dd>
	<dt><code>CONSIDER_OFFLINE_AFTER</code></dt>
	<dd>entries will be marked red if a system did not ping dyn.php for this many seconds. Set to 0 to disable.</dd>
</dl>


## API

`dyn.php` has two "modes".

### `http://example.com/dyn.php[?name=][&quiet]`

returns the current IP address in JSON format (unless `?quiet` is used, in which case nothing will be returned).

If `?name` is specified, the IP address will be remembered under this name and can be viewed later using `?out`.

### `http://example.com/dyn.php?out`

prints the IP addresses stored by previous `?name` updates after authentication.
