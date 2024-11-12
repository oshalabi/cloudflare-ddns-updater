# Cloudflare Dynamic DNS IP Updater

<img alt="GitHub" src="https://img.shields.io/github/license/oshalabi/cloudflare-ddns-updater?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/oshalabi/cloudflare-ddns-updater/main"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/oshalabi/cloudflare-ddns-updater">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a
custom domain name without a static IP! Written in pure BASH.

## Support Me

[![Donate Via Paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/OHalabi)

## Installation

```bash
git clone https://github.com/oshalabi/cloudflare-ddns-updater.git
```

If you want to read the logs in a separate folder run this command
Create a folder for logging

```bash
sudo mkdir -p /var/log/dns
```

## Usage

This script is used with crontab. Specify the frequency of execution through crontab.

```bash
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday 7 is also Sunday on some systems)
# │ │ │ │ │ ┌───────────── command to issue                               
# │ │ │ │ │ │
# │ │ │ │ │ │
# * * * * * /bin/bash {Location of the script}
```

## Tested Environments:

macOS Mojave version 10.14.6 (x86_64) <br />
AlmaLinux 9.3 (Linux kernel: 5.14.0 | x86_64) <br />
Debian Bullseye 11 (Linux kernel: 6.1.28 | aarch64) <br />

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference

This script is forked from [https://github.com/K0p1-Git/cloudflare-ddns-updater](K0p1-Git)

## License

[MIT](https://github.com/oshalabi/cloudflare-ddns-updater/blob/main/LICENSE)
