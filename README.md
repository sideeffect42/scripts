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

### Oinkoin

Oinkoin is a flutter app for helping you managing your expenses. No internet required.
[source code](https://github.com/emavgl/oinkoin)

* Convert spending records from CSV to Oinkoin's JSON format:
  [oinkoin/csv-to-oinkoin.py](oinkoin/csv-to-oinkoin.py).


### Petitboot

Scripts for the [Petitboot](https://open-power.github.io/petitboot/) bootloader.

* Generate a `petitboot.conf` file from the files in the `/boot` directory
  automatically:

  cf. [petitboot/update-petitboot.sh](petitboot/README.update-petitboot.md)


### XMPP client

* Migration of chat history between accounts:

  cf. [xmpp-client/migrate](xmpp-client/migrate).