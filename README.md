# height-export

## Setup on mac

``` sh
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ brew install asdf
$ brew install git
$ asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
$ asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git
$ git clone https://github.com/Finbits/height-export.git
$ cd height-export
$ asdf install
```

## Usage

1. Get you API secret key on https://finbits.height.app/settings/api
2. `HEIGHT_SECRET_KEY=$YOUR_SECRET_KEY_HERE elixir stories_export.exs`

A csv file and a json file will be created with all the stories in it.
