#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_name=""                                      # Which record you want to be synced
ttl="3600"                                          # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"

# Path to store the current IP
ip_file="/tmp/current_ip"
# Path for the custom log file
log_file=""                                         # /var/log/dns/cloudflare-ddns-${record_name}.log

###########################################
## Function to Log Messages
###########################################
log_message() {
  local message="$1"
  # Log to syslog
  logger "DDNS Updater: $message"
  # Log to specified file if log_file is set
  if [[ -n "$log_file" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DDNS Updater: $message" >> "$log_file"
  fi
}

###########################################
## Function to Send Notifications
###########################################
send_notification() {
  local message="$1"
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri --data-raw "{\"channel\": \"$slackchannel\", \"text\" : \"$message\"}"
  fi
  if [[ $discorduri != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw "{\"content\" : \"$message\"}" $discorduri
  fi
}

###########################################
## Retrieve Public IP
###########################################
ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -oP 'ip=\K[0-9.]+')
if [[ ! $ip =~ $ipv4_regex ]]; then
  # Fall back to alternative sources if the primary fails
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
fi

if [[ ! $ip =~ $ipv4_regex ]]; then
  log_message "Failed to find a valid IP."
  exit 2
fi
log_message "Retrieved IP: $ip"

###########################################
## Compare with Stored IP
###########################################
# Check if the stored IP file exists and read it if available
if [[ -f "$ip_file" ]]; then
  old_ip=$(cat "$ip_file")
else
  old_ip=""
fi

# If the IP hasn't changed, exit the script
if [[ "$ip" == "$old_ip" ]]; then
  log_message "IP ($ip) has not changed, no update needed."
  exit 0
else
   log_message "IP has changed from $old_ip to $ip. Update needed."
fi

###########################################
## Update Stored IP
###########################################
# Save the current IP to the file
echo "$ip" > "$ip_file"

###########################################
## Set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Fetch the A Record from Cloudflare
###########################################
log_message "DDNS Updater: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

if [[ -z "$record" ]]; then
  log_message "Failed to retrieve A record for $record_name."
  exit 1
fi

###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  log_message "Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
ip_cloudflare=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $ip == $ip_cloudflare ]]; then
  log_message "IP ($ip_cloudflare) for ${record_name} has not changed."
  exit 0
fi
###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

###########################################
## Update IP@Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")

if [[ -z "$update" ]]; then
  log_message "Failed to update the IP for $record_name."
  exit 1
fi

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  log_message "DDNS Updater: Update failed for $record_name with IP $ip. Result:\n$update"
  send_notification "$sitename DDNS Update Failed: $record_name with IP $ip."
  exit 1;;
*)
  log_message "IP for $record_name updated to $ip."
  send_notification "$sitename Updated: $record_name's new IP Address is $ip"
  exit 0;;
esac
