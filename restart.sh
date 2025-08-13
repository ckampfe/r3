#!/usr/bin/env sh

launchctl unload ~/Library/LaunchAgents/ckampfe.r3.plist
launchctl load -w ~/Library/LaunchAgents/ckampfe.r3.plist
