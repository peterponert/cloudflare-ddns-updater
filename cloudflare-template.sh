#!/bin/bash
##
## DDNS WebHook / Cloudflare API DNS Record Updater
##
## DESRIPTION:
## BASH Script to send current determined Public IP address to 

## REQUIREMENTS:
## jq, dig

## CREDITS:
## - Refactor based off https://github.com/K0p1-Git/cloudflare-ddns-updater   (Work in progress)

## NOTES:
#############################################################################################
## change to "bin/sh" when necessary
## requires jq installed
## Use: log show --predicate 'process == "logger"' --last 5m   (On macOS)



## Cloudflare Info:
auth_email="@gmail.com"                             # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
ttl="3600"                                          # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
record_name=""                                      # Which record you want to be synced

## Miscellaneous WebHooks
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"


## Access logs via

## Check and set the proper auth header
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi


## Check if we have a public IP

## Services
#dig @resolver4.opendns.com myip.opendns.com +short
#dig @ns1.google.com TXT o-o.myaddr.l.google.com +short
#dig TXT o-o.myaddr.l.google.com @ns1.google.com +short
#ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip' | sed -r 's/^ip=(.*)/\1/')

ipService="o-o.myaddr.l.google.com"

ip=$(dig TXT o-o.myaddr.l.google.com @ns1.google.com +short | xargs);

if [[ $ip =~ .*:.* ]]; then
  ipVersion='6'
  ipType='AAAA'
else
  ipVersion='4'
  ipType='A'
fi

ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
ipv6_regex='(([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4})'

# Use regex to check for proper IPv4 format.
#if [[ ! $ip =~ ^$ipv6_regex$ ]]; then
#    logger -s "DDNS Updater: Failed to find a valid IPv6."
    #exit 2
#else [[ ! $ip =~ ^$ipv4_regex$ ]]; then
#    logger -s "DDNS Updater: Failed to find a valid IP."
    #exit 2
#fi

echo
echo "Current External IP: $ip  IPv$ipVersion [$ipType] Record   ($ipService)"



## Change the IP@Cloudflare using the API
createRecord ()
{
  create=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records" \
     -H "X-Auth-Email: $auth_email" \
     -H "$auth_header $auth_key" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"$1\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"priority\":10,\"proxied\":${proxy},\"comment\":\"DDNS script\"}")
  echo "                     Created [$1] Record"
}



## Seek for the A or AAAA record
seekForRecordType ()
{
  logger "DDNS Updater: Check Initiated"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=$1&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")
  if [[ !( $record == *"\"count\":0"* ) ]]; then
    old_ip=$(echo "$record" | jq -r '.result[].content')
    echo "                     Found Existing [$1] Record ($(echo "$record" | jq -r '.result[].id'))"
  else
    if  [[ $2 == "CreateNewEnabled" ]]; then
      logger -s "DDNS Updater: created (${ip} for ${record_name})"
      createRecord $ipType
      old_ip="$(echo "$record" | jq -r '.result[].content')"
    fi
  fi
  record_identifier=$(echo "$record" | jq -r '.result[].id')
}



## Change the IP@Cloudflare using the API
updateRecord ()
{
  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$1" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"$ipType\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")
  echo "                     Updated [$ipType] Record $1"
}


seekForRecordType $ipType "CreateNewEnabled"

## Check if Update Necessary
record_identifier=$(echo "$record" | jq -r '.result[].id')
echo "            DDNS IP: $old_ip"
echo "         Current IP: $ip"

if [[ $ip == $old_ip ]]; then
  echo " Current DNS Record: [$ipType] [$record_name] [$ip]"
  logger "DDNS Updater: IP ($ip) for ${record_name} has not changed."
else
  updateRecord $record_identifier
fi



## Clean the old IP@Cloudflare using the API
cleanOtherRecord ()
{  
  clean=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$1" \
     -H "X-Auth-Email: $auth_email" \
     -H "$auth_header $auth_key" \
     -H "Content-Type: application/json")
}



if [[ $ipVersion == '4' ]]; then
  seekForRecordType 'AAAA'
  if [[ !( $record == *"\"count\":0"* ) ]]; then
    cleanOtherRecord $record_identifier
    echo "                     Removed Duplicate Record ($record_identifier)" 
    exit 0
  fi
  echo "                     [AAAA] Record Not Found"
else
  seekForRecordType 'A'
  if [[ !( $record == *"\"count\":0"* ) ]]; then
    cleanOtherRecord $record_identifier
    echo "                     Removed duplicate Record ($record_identifier)"
    exit 0
  fi
  echo "                     [A] Record Not Found"
fi

exit 0






###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  echo -e "DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s 
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
    }'
  fi
  if [[ $discorduri != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"$sitename"' DDNS Update Failed: '$record_name': '$record_identifier' ('$ip')."
    }' $discorduri
  fi
  exit 1;
*)
  logger "DDNS Updater: $ip $record_name DDNS updated."
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri \
    --data-raw '{
      "channel": "'$slackchannel'",
      "text" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
    }'
  fi
  if [[ $discorduri != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
    --data-raw '{
      "content" : "'"$sitename"' Updated: '$record_name''"'"'s'""' new IP Address is '$ip'"
    }' $discorduri
  fi
  exit 0;;
esac
