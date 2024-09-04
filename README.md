# scripts

Random collection of shell scripts (of varying quality).

```c
/**
 * You are solely responsible for the actions you take with your electronic
 * devices. Any instructions and/or scripts presented in this repository are
 * merely a (seemingly) random collection of scripts I had once written and
 * found they could be useful for other people, too. The guides are simply a
 * record of the steps I took to achieve my personal goals on my device(s).
 * Just because they worked this way for me does not imply that they work
 * equally well (or at all) for your use case!
 *
 * As a result, I CAN NOT BE HELD LIABLE for any damage that might occur to your
 * personal or other people's data, software, and/or hardware.
 *
 * It is very(!) advisable to study the source code of all the scripts found in
 * this repository before executing them.
 * Please do your own research prior to executing any commands that you do not
 * fully understand.
 */
```

-----


### Dynamic DNS

* Tiny PHP CGI script to monitor the current public IPv4 address of systems.

  cf. [dyndns/dyn.php](dyndns/dyn.php)


### Oinkoin

Oinkoin is a flutter app for helping you managing your expenses. No internet required.
[source code](https://github.com/emavgl/oinkoin)

* Convert spending records from CSV to Oinkoin's JSON format:
  [oinkoin/csv-to-oinkoin.py](oinkoin/csv-to-oinkoin.py).


### OpenWrt

Scripts for use with [OpenWrt](https://www.openwrt.org).

* Automatic resizing of the root file system:

  cf. [openwrt/resize.sh](openwrt/README.resize.md)


### Petitboot

Scripts for the [Petitboot](https://open-power.github.io/petitboot/) bootloader.

* Generate a `petitboot.conf` file from the files in the `/boot` directory
  automatically:

  cf. [petitboot/update-petitboot.sh](petitboot/README.update-petitboot.md)


### SVN

Scripts for the [Subversion](https://subversion.apache.org) version control
system.

* Rewrite the commit authors:

  cf. [svn/update-authors.sh](svn/update-authors.sh)

### TV7

Scripts to use Init7's [TV7](https://www.init7.net/en/tv/tv7/) with your own 
TV headend.

* CLI to the TV7 API written in Python.

  It supports:
  * M3U playlist generation using both multicast and HLS URLs
  * XMLTV generation

  cf. [tv7/tv7.py](tv7/tv7.py)

* Helper script to use tv7.py as an EPG source in [TVheadend](https://tvheadend.org/): [tv7/tv_grab_tv7](tv7/tv_grab_tv7)


### XMPP client

* Migration of chat history between accounts:

  cf. [xmpp-client/migrate](xmpp-client/migrate).
