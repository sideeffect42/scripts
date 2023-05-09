# Migrate XMPP client chat history

When you move to a new XMPP provider you usually lose the old chat history when
the old account is removed from the XMPP client.

This directory contains scripts for different XMPP clients which try to migrate
the chat history from one account to another as good as possible.

**ALWAYS make a backup first!**

These scripts work with the internal database of the respective client.
Thus, they may not work with all versions of the client and, in the worst case,
could destroy the complete application database!

## BeagleIM

The `beagleim-move-history.sh` updates the chat history and related information
to belong to another account.
If this account is then created, the moved chat histories will be visible again.

In any case it is recommended to remove the old account afterwards, since parts
of the information attached to it were moved (not copied) to another accont.

How to use the script:

1.	Close the BeagleIM app,
2.	execute in a Terminal:
	```sh
	sh beagleim-move-history.sh [old jid] [new jid]
	```` 
	(JID is your XMPP user name, e.g. user@example.com)
3.	start BeagleIM,
4.	add the new account,
5.	remove the old account.

In case something should go wrong, the script creates a backup of the BeagleIM
database at `~/Library/Containers/org.tigase.messenger.BeagleIM/Data/Library/Application\ Support/BeagleIM/beagleim.sqlite.bak`.

## Dino

The `rename-dino-account.sh` changes the JID of an already existing account.
This way, all information attached to the old account will be moved to the new
account.

How to use the script:

1.	Close Dino,
2.	execute in a terminal window:
	```sh
	sh rename-dino-account.sh [old jid] [new jid]
	```
	(JID is your XMPP user name, e.g. user@example.com)
4.	start Dino,
5.	open the Accounts window and fill in the password of your new account.

In case something should go wrong, the script creates a backup of the Dino
database at `~/.local/share/dino/dino.db.bak`.
