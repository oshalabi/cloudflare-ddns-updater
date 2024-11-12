#!/bin/bash
## change to "bin/sh" when necessary

##############  CLOUDFLARE CREDENTIALS  ##############
# @auth_email           - The email used to login 'https://dash.cloudflare.com'
# @auth_method          - Set to "global" for Global API Key or "token" for Scoped API Token
# @auth_key             - Your API Token or Global API Key
# @zone_identifier      - Can be found in the "Overview" tab of your domain
# -------------------------------------------------- #
auth_email=""
auth_method="token"
auth_key=""
zone_identifier=""

#############  DNS RECORD CONFIGURATION  #############
# @record_name          - Which record you want to be synced
# @ttl                  - DNS TTL (seconds), can be set between (30 if enterprise) 60 and 86400 seconds, or 1 for Automatic
# @proxy                - Set the proxy to true or false
# -------------------------------------------------- #
record_name=""
ttl=3600
proxy="false"

###############  SCRIPT CONFIGURATION  ###############
# @static_IPv6_mode     - Useful if you are using EUI-64 IPv6 address with SLAAC IPv6 suffix token. (Privacy Extensions)
#                       + Or some kind of static IPv6 assignment from DHCP server configuration, etc
#                       + If set to false, the IPv6 address will be acquired from external services
# @last_notable_hexes   - Used with `static_IPv6_mode`. Configure this to target what specific IPv6 address to search for
#                       + E.g. Your global primary IPv6 address is 2404:6800:4001:80e::59ec:ab12:34cd, then
#                       + You can put values (i.e. static suffixes) such as "34cd", "ab12:34cd" and etc
# @log_header_name      - Header name used for logs
# -------------------------------------------------- #
static_IPv6_mode="false"
last_notable_hexes="ffff:ffff"
log_header_name="DDNS Updater_v6"
log_file=""               # /var/log/dns/cloudflare-ddns-${record_name}.log
ip_file="/tmp/current_ipv6"

#############  WEBHOOKS CONFIGURATION  ###############
# @sitename             - Title of site "Example Site"
# @slackchannel         - Slack Channel #example
# @slackuri             - URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
# @discorduri           - URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"
# -------------------------------------------------- #
sitename=""
slackchannel=""
slackuri=""
discorduri=""

###########################################
## Function to Log Messages
###########################################
log_message() {
    local message="$1"
    logger "$log_header_name: $message"
    if [[ -n "$log_file" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_header_name: $message" >> "$log_file"
    fi
}

###########################################
## Function to Send Notifications
###########################################
send_notification() {
    local message="$1"
    if [[ -n "$slackuri" ]]; then
        curl -L -X POST "$slackuri" --data-raw "{\"channel\": \"$slackchannel\", \"text\": \"$message\"}"
    fi
    if [[ -n "$discorduri" ]]; then
        curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{\"content\": \"$message\"}" "$discorduri"
    fi
}

################################################
## Check IPv6 Connection
################################################
if ! { curl -6 -s --head --fail https://ipv6.google.com >/dev/null; }; then
    log_message "Unable to establish a valid IPv6 connection to a known host."
    exit 1
fi

################################################
## Find IPv6 Address
################################################
ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|...)"

if $static_IPv6_mode; then
    # Test whether 'ip' command is available
    if command -v "ip" &>/dev/null; then
        ip=$(ip -6 -o addr show scope global primary -deprecated | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    else
        # Fall back to 'ifconfig' command
        ip=$(ifconfig | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    fi
else
    # Use external services to discover our system's preferred IPv6 address
    ip=$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep -oP 'ip=\K[0-9a-fA-F:.]+')
    ret=$?
        if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
            # Attempt to get the ip from other websites.
            ip=$(curl -s -6 https://api64.ipify.org || curl -s -6 https://ipv6.icanhazip.com)
        else
            # Extract just the ip from the ip line from cloudflare.
            ip=$(echo $ip | sed -E "s/^ip=($ipv6_regex)$/\1/")
        fi
fi

if [[ ! $ip =~ $ipv6_regex ]]; then
    log_message "Failed to find a valid IPv6 address."
    exit 1
fi
log_message "Retrieved IPv6 Address: $ip"

################################################
## Compare with Stored IP
################################################
if [[ -f "$ip_file" ]]; then
    old_ip=$(cat "$ip_file")
else
    old_ip=""
fi

if [[ "$ip" == "$old_ip" ]]; then
    log_message "IPv6 ($ip) has not changed, no update needed."
    exit 0
else
    log_message "IPv6 has changed from $old_ip to $ip. Update needed."
fi

echo "$ip" > "$ip_file"

################################################
## Set the proper auth header
################################################
auth_header="Authorization: Bearer"
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
fi

################################################
## Fetch the AAAA Record from Cloudflare
################################################
log_message "Check Initiated for AAAA Record"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json")

if [[ $record == *"\"count\":0"* ]]; then
    log_message "Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
fi

################################################
## Get Existing IPv6 Address from Cloudflare
################################################
old_ip_cloudflare=$(echo "$record" | grep -oP '"content":"\K[^"]+')

# Make sure the extracted IPv6 address is valid
if [[ ! $old_ip_cloudflare =~ $ipv6_regex ]]; then
    log_message "Unable to extract existing IPv6 address from DNS record."
    exit 1
fi

# Compare if they're the same
if [[ $ip == $old_ip_cloudflare ]]; then
    log_message "IPv6 ($old_ip_cloudflare) for ${record_name} has not changed on Cloudflare."
    exit 0
fi

################################################
## Set the record identifier from result
################################################
record_identifier=$(echo "$record" | grep -oP '"id":"\K[^"]+')

################################################
## Update IPv6 on Cloudflare
################################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")

################################################
## Report the Status
################################################
if [[ $update == *"\"success\":false"* ]]; then
    message="$log_header_name: $ip $record_name DDNS update failed for $record_identifier ($ip)"
    log_message "$message"
    send_notification "$sitename DDNS Update Failed: $record_name ($ip)."
    exit 1
else
    message="$log_header_name: IPv6 for $record_name updated to $ip."
    log_message "$message"
    send_notification "$sitename Updated: $record_name's new IPv6 Address is $ip"
    exit 0
fi
