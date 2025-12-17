#!/usr/bin/env bash
set -o errexit

echo "============================"
echo "🚀 CUSTOM BUILD STARTED"
echo "============================"

echo "🔑 RAILS_MASTER_KEY = ${RAILS_MASTER_KEY:0:4}...(truncated)"

bundle install
bundle exec rake assets:precompile
