# height-export

## Setup on mac

``` sh
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ brew install git asdf autoconf openssl wxwidgets libxslt fop unzip
$ asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
$ asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git
$ git clone https://github.com/Finbits/height-export.git
$ cd height-export
$ asdf install
```

## Usage

Get you API secret key on https://finbits.height.app/settings/api

``` sh
$ export HEIGHT_SECRET_KEY=YOUR_SECRET_KEY_HERE
$ elixir height_export.exs
```

A csv file and a json file will be created with all the stories in it.

We can also export tasks from other lists:

``` sh
$ elixir height_export.exs --list sup
```

