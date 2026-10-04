# ishtaria-client

Godot 4 client of Ishtaria. Linux x86-64 only, distributed as a Debian package.

**Status:** M0 – preview scene (planet and orbit camera), no server connection yet.

## Installation

Debian / Ubuntu (x86-64) only:

```sh
echo "deb http://repo.vitexsoftware.com $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/vitexsoftware.list
sudo wget -O /etc/apt/trusted.gpg.d/vitexsoftware.gpg http://repo.vitexsoftware.com/keyring.gpg
sudo apt update
sudo apt install ishtaria-client
```

## Development

Open the folder in Godot 4.5. To build the package:

```sh
tools/fetch-godot.sh            # Godot 4.5 + Linux export templates
dpkg-buildpackage -us -uc -b
```

License: MIT

## Part of Ishtaria

Ishtaria is an open-source, persistent, federated virtual planet of Earth size.
Documentation: https://vitexsoftware.github.io/ishtaria-docs/ · All repositories: https://github.com/VitexSoftware?q=ishtaria
