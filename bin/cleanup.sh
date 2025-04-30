#!/bin/bash

# Import local environment specific settings
ENV_FILE="${PWD}/.env"
if [ ! -f $ENV_FILE ]; then
    echo "An '.env' file was not found in ${PWD}"
    exit 1
fi
source .env
AppName=$SSC_APP_NAME
ScanSwitches="-Dcom.fortify.sca.ProjectRoot=.fortify"

if [ -z "${AppName}" ]; then
    echo "Application Name has not been set in '.env'"; exit 1
fi

echo Removing files...
sourceanalyzer $ScanSwitches -b "$AppName" -clean
rm -rf .fortify
rm -f "${AppName}.fpr"
rm -f "${AppName}.pdf"
rm -f "fod.zip"
rm -f "*Package.zip"
rm -f "fortifypackage.zip"
rm -rf ".debricked"
rm -rf "instance"
rm -f "*.lock"
rm -f "*.log"
rm -f "dependencies.txt"
rm -f ".gradle-init-script.debricked.groovy"
echo Done.
