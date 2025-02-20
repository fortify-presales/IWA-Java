#!/bin/bash
#
# Example script to perform Fortify ScanCentral SAST scan
#

# Retrieve parameters
SkipPDF=1
SkipSSC=1
while [[ "$#" -gt 0 ]]; do
    case $1 in
	    -p|--scan-policy) ScanPolicy="$2"; shift ;;
        --create-pdf) SkipPDF=0 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done
if [ -z "$ScanPolicy" ]; then
    ScanPolicy="classic"
fi
echo "Using ScanPolicy: ${ScanPolicy}"
if [ $SkipPDF -eq 1 ]; then
    echo "... skipping PDF generation"
fi

# Import local environment specific settings
ENV_FILE="${PWD}/.env"
if [ ! -f $ENV_FILE ]; then
    echo "An '.env' file was not found in ${PWD}"
    exit 1
fi
source .env
AppName=$SSC_APP_NAME
AppVersion=$SSC_APP_VER_NAME
SSCUrl=$SSC_URL
ScanCentralCtrlUrl=$SCANCENTRAL_CTRL_URL
ScanCentralEmail=$SCANCENTRAL_EMAIL
SSCAuthToken=$SSC_AUTH_TOKEN # AnalysisUploadToken
JVMArgs="-Xss256M"
ScanSwitches="-Dcom.fortify.sca.ProjectRoot=.fortify"
PackageName="ScanCentralPackage.zip"

if [ -z "${AppName}" ]; then
    echo "Application Name has not been set in '.env'"; exit 1
fi
if [ -z "${AppVersion}" ]; then
    echo "Application Version has not been set in '.env'"; exit 1
fi
if [ -z "${ScanCentralCtrlUrl}" ]; then
    echo "ScanCentral Controller URL has not been set in '.env'"; exit 1
fi
if [ -z "${SSCAuthToken}" ]; then
    echo "SSC Authentication Token has not been set in '.env'"; exit 1
fi
if [ -z "${ScanCentralEmail}" ]; then
    ScanCentralEmail="sscuser@cyberxdemo.com"
fi

# Delete Package if it already exists
if [ -f $PackageName ]; then
   rm -f $PackageName
fi

# Package, upload and run the scan and import results into SSC
#
echo Invoking ScanCentral SAST ...
scancentral -url $ScanCentralCtrlUrl start -upload -uptoken $SSCAuthToken -sp $PackageName \
    -application "$AppName" -version "$AppVersion" -bt gradle -bf build.gradle -bc "clean build -x test" \
    -exclude "src/main/resources/schema.sql" -exclude "src/main/resources/data.sql" \
    -email $ScanCentralEmail -block -o -f "${AppName}.fpr" -rules etc/sast-custom-rules/example-custom-rules.xml -filter etc/sast-filters/example-filter.txt \
    -sargs "${ScanArgs}"

# summarise issue count by analyzer
FPRUtility -information -analyzerIssueCounts -project "${AppName}.fpr"

if [ $SkipPDF -eq 0 ]; then
    echo Generating PDF report...
    ReportGenerator $ScanSwitches -user "Demo User" -format pdf -f "${AppName}.pdf" -source "${AppName}.fpr"
fi

echo Done.
