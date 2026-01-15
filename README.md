[![Build and Test](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/build.yml/badge.svg)](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/build.yml)

[![OpenText FoD](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/fod.yml/badge.svg)](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/fod.yml)
[![OpenText ScanCentral](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/scancentral.yml/badge.svg)](https://github.com/fortify-presales/IWA-PharmacyDirect/actions/workflows/scancentral.yml)

# IWA (Insecure Web App) Pharmacy Direct

#### Table of Contents

*   [Overview](#overview)
*   [Forking the Repository](#forking-the-repository)
*   [Building the Application](#building-the-application)
*   [Running the Application](#running-the-application)
*   [Application Security Testing Integrations](#application-security-testing-integrations)
    * [SAST using Fortify SCA command line](#sast-using-fortify-sca-command-line)
    * [SAST using Fortify ScanCentral SAST](#sast-using-fortify-scancentral-sast)
    * [SAST using Fortify on Demand](#sast-using-fortify-on-demand)
    * [DAST using Fortify WebInspect](#dast-using-fortify-webinspect)
    * [DAST using Fortify ScanCentral DAST](#dast-using-fortify-scancentral-dast)
    * [DAST using Fortify on Demand](#dast-using-fortify-on-demand)
    * [API Security Testing using Fortify WebInspect and Postman](#api-security-testing-using-fortify-webinspect-and-postman)
    * [API Security Testing using ScanCentral DAST](#api-security-testing-using-scancentral-dast-and-postman)
    * [API Security Testing using Fortify on Demand](#api-security-testing-using-fortify-on-demand)
    * [FAST Using ScanCentral DAST and FAST proxy](#fast-using-scancentral-dast-and-fast-proxy)
*   [Build and Pipeline Integrations](#build-and-pipeline-integrations)
    * [Jenkins Pipeline](#jenkins-pipeline)
    * [GitHub Actions](#github-actions)
    * [Other Pipeline Tools](#other-pipeline-tools)
*   [Developing and Contributing](#developing-and-contributing)
*   [Licensing](#licensing)

## Notice

**For an "official" version of this application with additional pipeline integrations please visit [https://github.com/fortify/IWA-Java](https://github.com/fortify/IWA-Java).**

## Overview

_IWA (Insecure Web App) Pharmacy Direct_ is an example Java/Spring Web Application for use in **DevSecOps** scenarios and demonstrations.
It includes some examples of bad and insecure code - which can be found using static and dynamic application
security testing tools such as those provided by [OpenText Application Security](https://www.microfocus.com/en-us/cyberres/application-security).

One of the main aims of this project is to illustrate how security can be embedded early ("Shift-Left") and continuously ("CI/CD") in
the development lifecycle. Therefore, a number of examples of "integrations" to common CI/CD pipeline tools are provided.

The application is intended to provide the functionality of a typical "online pharmacy", including purchasing Products (medication)
and requesting Services (prescriptions, health checks etc). It has a modern-ish HTML front end (with some JavaScript) and a Swagger based API.

*Please note: the application should not be used in a production environment!*

![Screenshot](media/screenshot.png)

## Forking the Repository

In order to execute example scenarios for yourself, it is recommended that you "fork" a copy of this repository into
your own GitHub account. The process of "forking" is described in detail in the [GitHub documentation](https://docs.github.com/en/github/getting-started-with-github/fork-a-repo) - you can start the process by clicking on the "Fork" button at the top right.

## Build Requirements

In order to successfully build and run the application you will need to have [Java JDK 11](https://openjdk.org/projects/jdk/11) 
installed and on your path.

## Building the Application

To build the application using Gradle, execute the following from the command line:

```PowerShell
.\gradlew clean build
```

## Running the Application

There are a number of ways of running the application depending on the scenario(s) that you wish to execute.

### Development (IDE/command line)

To run (and test) locally in development mode, execute the following from the command line:

```PowerShell
.\gradlew bootRun
```

Then navigate to the URL: [http://localhost:8888](http://localhost:8888). You can carry out a number of
actions unauthenticated, but if you want to log in you can use the following credentials:

- **user1/password**
  
There is also an administrative user:

- **admin/password**

Note: if you log in with the `user2` account you will be subsequently asked for a Multi-Factor Authentication (MFA) code; the code is printed in the application console.

### Docker Image

The JAR file can also be built into a Docker image using the provided `Dockerfile` and the
following commands:

```PowerShell
docker build -t iwa -f Dockerfile .
```

This image can then be executed using the following commands:

```PowerShell
docker run -d -p 8888:8888 \
  -e SPRING_MAIL_HOST=smtp.example.com \
  -e SPRING_MAIL_PORT=587 \
  -e SPRING_MAIL_USERNAME=youruser \
  -e SPRING_MAIL_PASSWORD=yourpassword \
  -e SPRING_MAIL_TEST_CONNECTION=true \
  iwa
```

#### Dockerfile notes

- The `docker-entrypoint.sh` script will only wait for the mail server when `SPRING_MAIL_HOST` and `SPRING_MAIL_PORT` are set and `SPRING_MAIL_TEST_CONNECTION` is enabled. This avoids unnecessary blocking for deployments that do not use mail.
- A built-in healthcheck is available in the Dockerfile that queries the application's HTTP health endpoint (`/actuator/health`). When running a container in orchestration platforms this allows the platform to know when the app is healthy.

### Health/Actuator endpoint

The application exposes Spring Boot Actuator endpoints. The health endpoint is available at `/actuator/health` on the application's 
HTTP port (the app uses the configured `server.port`, default in development is `8888`).
- You can test the health endpoint from PowerShell using the following command (PowerShell equivalent of `curl -i`):

```PowerShell
# Show raw response headers and body
Invoke-WebRequest -Uri http://localhost:8888/actuator/health -UseBasicParsing | Select-Object StatusCode, Headers, Content

# Or get the JSON body directly
Invoke-RestMethod -Uri http://localhost:8888/actuator/health
```

### Development Email Server

If you would like to use a development email server, I recommend using smtp4dev: https://github.com/rnwood/smtp4dev.
The easiest approach is to start it as a docker container:

```
docker run --rm -it -p 5000:80 -p 2525:25 rnwood/smtp4dev
```

Remove `--rm -it` if you want to leave smtp4dev running in the background.

The `application-dev.yml` file is already pre-configured to use smtp4dev for local development.
By default the application reads mail configuration from Spring Boot properties which can be provided via environment variables when running in Docker or cloud environments.

Environment variables supported (recommended names):

- SPRING_MAIL_HOST (e.g. smtp4dev host or smtp.gmail.com)
- SPRING_MAIL_PORT (e.g. 25, 587, 2525)
- SPRING_MAIL_USERNAME (mail username if required)
- SPRING_MAIL_PASSWORD (mail password or app password)
- SPRING_MAIL_DEFAULT_ENCODING (default: UTF-8)
- SPRING_MAIL_TEST_CONNECTION (true|false) — when true the Docker entrypoint will try to connect to the mail server at startup and wait (useful to avoid failures when mail is required). Default: true
- SPRING_MAIL_CONNECT_TIMEOUT (seconds) — how long the entrypoint will wait for the mail server before continuing (default: 15)
- SPRING_MAIL_DEBUG (true|false) — enable JavaMail debug output (optional)

Note: These environment variables are mapped by Spring Boot to the equivalent properties used by the application (for example SPRING_MAIL_HOST -> spring.mail.host). The project entrypoint (`docker-entrypoint.sh`) is already implemented to wait for the mail server only when `SPRING_MAIL_HOST` and `SPRING_MAIL_PORT` are set and `SPRING_MAIL_TEST_CONNECTION` is not `false`/`0`.

Example: run the application with smtp4dev (host.docker.internal lets the container reach a locally running smtp4dev on the Docker host):

```
docker build -t iwa -f Dockerfile .

docker run --rm -p 8888:8888 \
  -e SPRING_MAIL_HOST=host.docker.internal \
  -e SPRING_MAIL_PORT=2525 \
  -e SPRING_MAIL_TEST_CONNECTION=true \
  iwa
```

If you don't want the container to wait for mail at startup (for example in environments where mail is optional) set:

```
-e SPRING_MAIL_TEST_CONNECTION=false
```

## Deploying the Application

You can deploy the containerised application to Azure using the included PowerShell helper script `deploy.ps1`. The script will optionally build a local Docker image, push it to an Azure Container Registry (ACR), create or update a Web App, and apply application settings defined in a `deploy.config` file or environment variables.

Prerequisites

- Docker installed and running.
- Azure CLI (`az`) installed and authenticated (`az login`).
- Optional: permission to create resource groups / app plans / web apps in the target subscription.

Quick preview (dry-run)

Before making any changes you can preview the effective configuration the script will use:

```powershell
# Show resolved configuration in a neat table (values masked by default)
.\deploy.ps1 -WhatIfConfig

# Show which environment variable names were checked and reveal unmasked values for debugging
.\deploy.ps1 -WhatIfConfig -Verbose -Debug
```

A few important notes about how `deploy.ps1` configures containers and app settings:

- When deploying to an App Service plan that is Linux and an ACR image is available, `deploy.ps1` will attempt to supply the container image and registry settings at create-time (using the Azure CLI create flags). This reduces the number of Azure CLI calls and avoids later deprecation warnings.
- Immediately after `az webapp create` the script verifies the Web App's container configuration. If the expected image is not present (or cannot be read), the script will automatically fall back to `az webapp config container set` to apply the container image and registry settings, and will re-check success.
- The script logs the final full image reference it will push and deploy. Look for the cyan log line printed before tagging/pushing: `Final ACR image reference to push: <acrLoginServer>/<image>:<tag>` — this helps confirm there is no accidental double-prefixing of the registry host.
- `-WhatIfConfig` prints a neat table of the effective configuration (including keys from the `[env]` section that would be applied as app settings). By default secret-looking values are masked; pass PowerShell's built-in `-Debug` common parameter (together with `-WhatIfConfig`) to reveal unmasked values for debugging.

# Key behaviour and precedence

- Configuration precedence (highest -> lowest):
  1. Script parameters passed on the command line (e.g. `-ResourceGroup my-rg`).
  2. Environment variables (section-prefixed or generic UPPER_SNAKE names).
  3. Values in `deploy.config` (the file is optional — the script will create no changes if it's absent).

- Environment variable naming:
  - For parameters defined in a section of `deploy.config`, the script looks first for a section-prefixed variable in UPPER_SNAKE form (for example `AZURE_ACR_NAME` for `AcrName` in the `[azure]` section).
  - Then it checks the generic UPPER_SNAKE name (for example `ACR_NAME`).
  - For `[env]` entries (application settings) the script prefers the exact name (for example `SPRING_MAIL_HOST`) but will also check section-prefixed names.

Example `deploy.config`

Place this file next to `deploy.ps1` as `deploy.config` to provide defaults and grouped sections. Values can be overridden by environment variables or script parameters.

```ini
[azure]
AcrName = iwadevuks
ResourceGroup = rg-iwa-dev-uks-001
Location = uksouth
PlanName = iwa-webapp-dev-uks-001

[docker]
ImageName = iwa
Tag = latest
Build = true

[env]
SPRING_MAIL_HOST = smtp.gmail.com
SPRING_MAIL_PORT = 587
SPRING_MAIL_USERNAME = youruser
SPRING_MAIL_PASSWORD = yourpassword
SPRING_MAIL_DEFAULT_ENCODING = UTF-8
SPRING_MAIL_TEST_CONNECTION = true
```

Common deploy scenarios

- Build locally, push to ACR and deploy to Web App (using CLI args):

```powershell
.\deploy.ps1 -ResourceGroup rg-iwa-dev-uks-001 -AcrName iwadevuks -AppName iwajava -ImageName iwa -Build -WaitFor
```

- Use `deploy.config` + environment variables (no CLI arguments):

```powershell
$env:AZURE_ACR_NAME = 'iwadevuks'
$env:AZURE_RESOURCE_GROUP = 'rg-iwa-dev-uks-001'
.\deploy.ps1 -ImageName iwa -Build -WaitFor
```

- Deploy but do not block waiting for mail server checks (useful for cloud environments):

```powershell
# Disable the entrypoint's mail-server wait logic
$env:SPRING_MAIL_TEST_CONNECTION = 'false'
.\deploy.ps1 -ResourceGroup rg-iwa-dev-uks-001 -AcrName iwadevuks -AppName iwajava -ImageName iwa -Build
```

Useful options

- `-WhatIfConfig` — Print the effective configuration (table) and exit. Use `-Verbose` to show which env var names were checked. Pass PowerShell's built-in `-Debug` to reveal unmasked secret values.
- `-Build` — Build the Docker image locally before tagging and pushing to ACR.
- `-WaitFor` — After restarting the Web App the script will poll Azure until the Web App reports the `Running` state (useful in CI). Configure timeout/interval with `-WaitTimeoutSeconds` and `-WaitIntervalSeconds`.

Notes

- Application settings defined in the `[env]` section of `deploy.config` are applied to the Azure Web App and become environment variables for the running container (for example `SPRING_MAIL_HOST`).
- DOCKER/ACR credentials may be obtained automatically via the Azure CLI; you can also provide `AcrUser`/`AcrPass` via env/config/CLI if required.
- The script is conservative by default: it masks sensitive values in `-WhatIfConfig` output unless you explicitly request unmasked output with `-Debug`.

## Application Security Testing Integrations

### SAST using Fortify SCA command line

This project includes a helper script `scan.ps1` to run an OpenText (Fortify) SCA translation and scan using the local Gradle build. The script packages, translates and runs a SAST scan and produces standard Fortify outputs (FPR, PDF). Use this script when you have a local Fortify SCA/OpenText SAST installation available.

What you need

- Fortify Static Code Analyzer / OpenText SCA tools installed and available on PATH (commands such as `sourceanalyzer`, `ReportGenerator` or `auditworkbench` should be callable).
- PowerShell (Windows PowerShell or PowerShell Core/pwsh).
- Java JDK 11 and a successful project build (the script runs Gradle build as part of the flow).

Quick example

Open a PowerShell prompt in the repository root and run:

```powershell
# Run the scan script which will build, translate and run a Fortify SCA scan
.\scan.ps1
```

What the script does (high level)

- Builds the project using Gradle (runs `./gradlew clean build -x test`).
- Runs Fortify `sourceanalyzer` translation step to collect project source and compile data.
- Runs the Fortify scan step to produce an FPR file (default name: `IWA-PharmacyDirect.fpr`).
- Optionally generates a PDF report (if `ReportGenerator` is available).

Configuration and common options

- The script reads configuration values from `fortify.config` (if present) and may accept additional parameters. See the header of `scan.ps1` for available command-line options.
- Common environment/config values you may need to set for upload to SSC or other tools are described elsewhere in this README (for example `SSC_URL`, `SSC_AUTH_TOKEN`, `SSC_APP_NAME`, `SSC_APP_VER_NAME`).

Typical outputs

- `IWA-PharmacyDirect.fpr` — Fortify Project Results file containing SAST findings.
- `IWA-PharmacyDirect.pdf` — (Optional) PDF report generated from the FPR if the report tool is installed.
- Exit code 0 indicates a successful scan; non-zero indicates failures in build/translate/scan steps.

Uploading results to Fortify Software Security Center (SSC)

If you want the script to upload results to SSC you will need an SSC CI token and the `SSC_*` configuration entries set (see the SSC sections later in this README). After running the scan you can upload the FPR using the appropriate tool or the `fcli` utilities described elsewhere.

Troubleshooting

- If `sourceanalyzer` is not found, ensure your Fortify/OpenText SCA installation is correctly installed and the bin folder is on PATH.
- The translation step may fail if the Gradle build fails; try running `./gradlew clean build` and fix any build issues first.
- If the script fails while generating reports, ensure `ReportGenerator` (or `auditworkbench`) is installed and configured.

See also

- `fortify.config` — sample Fortify configuration used by the project scripts.
- `scan.ps1` — the actual PowerShell script (open it to review supported flags and behaviour).

### SAST using Fortify ScanCentral SAST

There is a PowerShell script [scancentral-sast-scan.ps1](bin/scancentral-sast-scan.ps1) that you can use to package
up the project and initiate a remote scan using Fortify ScanCentral SAST:

```PowerShell
.\\bin\\scancentral-sast-scan.ps1
```

In order to use ScanCentral SAST you will need to have entries in the `.env` similar to the following:

```
SSC_URL=http://localhost:8080/ssc
SSC_AUTH_TOKEN=6b16aa46-35d7-4ea6-98c1-8b780851fb37
SSC_APP_NAME=IWA-PharmacyDirect
SSC_APP_VER_NAME=main
SCANCENTRAL_CTRL_URL=http://localhost:8080/scancentral-ctrl
SCANCENTRAL_CTRL_TOKEN=96846342-1349-4e36-b94f-11ed96b9a1e3
SCANCENTRAL_POOL_ID=00000000-0000-0000-0000-000000000002
SCANCENTRAL_EMAIL=test@test.com
```

The `SSC_AUTH_TOKEN` entry should be set to the value of a 'CIToken' created in SSC _"Administration->Token Management"_.

### AI Remediation using Fortify Aviator

To audit the results in SSC using Fortify Aviator, you can use the following commands.

```
fcli aviator session login -t env:AVIATOR_TOKEN --url https://ams.aviator.fortify.com
fcli ssc session login
fcli aviator ssc audit --app YOUR_APP --av YOUR_APP:YOUR_RELEASE
```

Note: you will need to have a Fortify Aviator entitlement and have created and configured `YOUR_APP` in your tenant first.

### SAST using Fortify on Demand

To execute a [Fortify on Demand](https://www.microfocus.com/en-us/products/application-security-testing/overview) SAST scan
you need to package and upload the source code to Fortify on Demand. To package the code into a Zip file for uploading
you can use the `scancentral` command utility as following:

```PowerShell
scancentral package -bt gradle -bf build.gradle -bt "clean build -x test" --output fod.zip
```

You can then upload this manually using the Fortify on Demand UI, using the [FoDUploader](https://github.com/fod-dev/fod-uploader-java) 
utility or via the [Fortify CLI](https://github.com/fortify/fcli) using the following commands:

```
fcli fod session login --url http://api.ams.fortify.com -t YOUR_FOD_TENANT -u YOUR_USERNAME -p YOUR_PASSWORD
fcli fod sast-scan start --release YOUR_APP:YOUR_RELEASE -f fod.zip --store curScan
fcli fod sast-scan wait-for ::curScan::
``` 

### DAST using Fortify WebInspect

To carry out a WebInspect scan you should first "run" the application using one of the steps described above.
Then you can start a scan using the following command line:

```PowerShell
"C:\Program Files\Fortify\Fortify WebInspect\WI.exe" -s ".\etc\IWA-UI-Dev-Settings.xml" -macro ".\etc\IWA-UI-Dev-Login.webmacro" -u "http://localhost:8888" -ep ".\IWA-DAST.fpr" -ps 1008
```

This will start a scan using the Default Settings and Login Macro files provided in the `etc` directory. It assumes
the application is running on "localhost:8888". It will run a "Critical and High Priority" scan using the policy with id 1008. 
Once completed you can open the WebInspect Desktop Client and navigate to the scan created for this execution. An FPR file
called `IWA-DAST.fpr` will also be available — you can open it with `auditworkbench` (or generate a PDF report using `ReportGenerator`). You could also upload it to Fortify SSC or Fortify on Demand.

There is an example PowerShell script file [webinspect-scan.ps1](bin/webinspect-scan.ps1) that you can run to execute the scan and upload the results to SSC:

```PowerShell
.\\bin\\webinspect-scan.ps1
```

### DAST using Fortify ScanCentral DAST

You can invoke a Fortify on Demand dynamic scan using the [FCLI](https://github.com/fortify/fcli) utility.
For example:

```
fcli sc-dast session login --ssc-url http://YOUR_SSC.DOMAIN -t YOUR_SSC_CI_TOKEN
fcli sc-dast scan -n "IWA-PharmacyDirect - FCLI" -s YOUR_SCAN_SETTINGS_ID --store curScan
fcli sc-dast scan wait-for ::curScan::
```

### DAST using Fortify on Demand

Fortify on Demand provides two means of carrying out DAST scanning: traditional DAST and _DAST Automated_.
In this section we will use _DAST Automated_ as this is more suitable for command- and pipeline-based integration.

You can invoke a Fortify on Demand _DAST Automated_ scan using the [FCLI](https://github.com/fortify/fcli) utility.
For example:

```
fcli fod session login --url http://api.ams.fortify.com -t YOUR_FOD_TENANT -u YOUR_USERNAME -p YOUR_PASSWORD
fcli fod dast-scan start --release YOUR_APP:YOUR_RELEASE --store curScan
fcli fod dast-scan wait-for ::curScan::
```

TBD: how to upload login macros and/or workflows.

### API Security Testing using Fortify WebInspect and Postman

The IWA application includes a fully documented [Swagger](https://swagger.io/solutions/getting-started-with-oas/) based 
API which you can browse to at 
[http://localhost:8888/swagger-ui/index.html?configUrl=/v3/api-docs/swagger-config](http://localhost:8888/swagger-ui/index.html?configUrl=/v3/api-docs/swagger-config).
You can carry out security testing of this API using Fortify WebInspect or ScanCentral DAST. A [Postman](https://www.postman.com/downloads/) 
collection is provided to help in this. You can exercise the collection using [newman](https://github.com/postmanlabs/newman). For example from a PowerShell
command prompt on Windows:

```PowerShell
newman run .\etc\IWA-API-Dev-Auth.postman_collection.json --environment .\etc\IWA-API-Dev.postman_environment.json --export-environment .\etc\IWA-API-Dev.postman_environment.json
newman run .\etc\IWA-API-Dev-Workflow.postman_collection.json --environment .\etc\IWA-API-Dev.postman_environment.json
```

In order to use this collection with WebInspect you will need to make sure newman is on the path and then you can run:

```PowerShell
& "C:\Program Files\Fortify\Fortify WebInspect\WI.exe" -pwc .\etc\IWA-API-Workflow.postman_collection.json -pec .\etc\IWA-API-Dev.postman_environment.json -ep ".\IWA-API.fpr"
```

### API Security Testing using ScanCentral DAST and Postman

Import the following Postman collections into ScanCentral DAST:

 - `etc\IWA-API-Prod.postman_environment.json`      - as Environment 
 - `etc\IWA-API-Auth.postman_collection.json`       - as Authentication Collection
 - `etc\IWA-API-Workflow.postman_collection.json`   - as Workflow collection

You will then need the following settings for the Dynamic Token Generation

Response Token:
```
"accessToken"\s*:\s*"(?<BearerTokenValue>[-a-zA-Z0-9._~+/]+?=*)"
```
Request Token:
```
Authorization:\sBearer\s(?<BearerTokenValue>[^\r\n]*)\r?\n
```
Logout Condition:
```
[STATUSCODE]401
```

The scan can be run from the ScanCentral DAST UI or via saving the settings and using the `fcli sc-dast scan` command.

### API Security Testing using Fortify on Demand

An API scan can be carried out using the following "combined" Postman collection:

 - `etc\IWA-API-Prod-Combined.postman_environment.json`

This can be used with either traditional DAST or _DAST Automated_.

### FAST Using ScanCentral DAST and FAST proxy

The Fortify FAST Proxy allows you to capture traffic from an automated test run and then use the traffic
as a workflow for a ScanCentral DAST execution. In order to carry out the example here you will need
to have installed WebInspect locally `WIRCServerSetup64-ProxyOnly.msi` which is available in the `Dynamic_Addons.zip` of the
ScanCentral DAST installation media.

There are some example Selenium scripts that can be used to execute a simple
functional test of the running application. There are also a couple of PowerShell scripts [start_fast_proxy.ps1](`.\bin\start_fast_proxy.ps1`) and [stop_fast_proxy.ps1](`.\bin\stop_fast_proxy.ps1`) that can
be used to start/stop the FAST Proxy. In order to use these scripts you will need to have entries in the `.env` file similar to the following:

```
APP_URL=http://localhost:8888
SSC_AUTH_TOKEN_BASE64=MmYyMTA5MzYtN2Q5Ny00NmM1LWI5NTUtYThkZWI2YmJlMDUy
SSCANCENTRAL_DAST_API=http://scancentral-dast-api.example.com/api/
SCANCENTRAL_DAST_CICD_IDENTIFIER=c3c3df60-de68-45b8-89c0-4c07b53392e7
FAST_PORT=8087
FAST_PROXY=127.0.0.1:8087
```

The `SSC_AUTH_TOKEN_BASE64` is the (first) encoded token shown in SSC not the (second) decoded token. 
Then carry out the following from the command line:

```
python -m pip install --upgrade pipenv wheel
pipenv shell
pipenv install --dev
```

Make sure the application is running and then execute the following in a terminal window:

```PowerShell
.\bin\start_fast_proxy.ps1
```

Then in another terminal window execute the following:

```PowerShell
pytest -v -s
```

And then finally:

```
.\bin\stop_fast_proxy.ps1
```

The FAST executable from the first terminal should terminate and then a scan execute in your ScanCentral DAST environment.

## Build and Pipeline Integrations

### Jenkins Pipeline

If you are using [Jenkins](https://jenkins.io/), a comprehensive `Jenkinsfile` is provided to automate the
typical steps of a DevSecOps Continuous Delivery (CD) process. The example makes use of Fortify ScanCentral SAST/DAST and
Sonatype Nexus IQ for Software Composition Analysis.

To make use of the `Jenkinsfile` create a new Jenkins *Pipeline* Job and in the *Pipeline* section select `Pipeline script from SCM` and enter the details of a forked version of this GitHub repository.

The first run of the pipeline should be treated as a "setup" step as it will create some *Job Parameters* which you can then select to determine which features you want to enable in the pipeline.

You will need to have installed and configured the [Fortify](https://plugins.jenkins.io/fortify/) Jenkins plugins.

The `Jenkinsfile` contains additional documentation — please review it for deployment details and options.

### GitHub Actions

This repository includes a number of [GitHub Actions](https://github.com/features/actions) examples in the [.github/workflows](.github/workflows/) that
automate the build of the application and scans the code using either
[Fortify on Demand](https://www.microfocus.com/en-us/products/application-security-testing) or [Fortify ScanCentral](https://www.microfocus.com/en-us/cyberres/application-security/static-code-analyzer) for SAST.

### Other Pipeline Tools

For integrations with other pipeline tools please see [https://github.com/fortify/IWA-Java](https://github.com/fortify/IWA-Java).

## Developing and Contributing

Please see the Contribution Guide (CONTRIBUTING.md) in this repository if present; otherwise open an Issue for contribution guidance.

If you have any problems, please consult [GitHub Issues](https://github.com/fortify-presales/IWA-PharmacyDirect/issues) to see if it has already been discussed.

## Licensing

This application is made available under the [GNU General Public License V3](LICENSE)
