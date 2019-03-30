# Ledger-Report

Simple tool to visualize the content of a [Ledger](http://www.ledger-cli.org/) file.

Does not support multiple currencies.

## Install

```
$ bundle install
```

## Configure

Copy `config.default.yml` to `config.yml` and edit `config.yml` to fit your needs.

Only the `en` and `fr` locales are currently supported (but others can easily be added).

## Run

```
$ ruby application.rb -o 0.0.0.0
```

Or

```
$ rerun "ruby application.rb -o 0.0.0.0"
```

Open `http://0.0.0.0:4567` in your browser.

## License

This tool is released under the terms of the MIT License. See the LICENSE.txt file for more details.