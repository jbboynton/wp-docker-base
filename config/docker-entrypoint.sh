#!/bin/bash -e

# Run pre-startup commands and routines here.
#
# Example: update the New Relic config for this environment
#
#   echo "newrelic.appname=${NEW_RELIC_APPNAME}" \
#     >> /usr/local/etc/php/conf.d/newrelic.ini

# Proceed with normal container startup
exec apache2-foreground
