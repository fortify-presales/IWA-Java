#!/usr/bin/env groovy

//****************************************************************************************************
// An example pipeline for DevSecOps using OpenText Fortify Application Security products
// @author: Kevin A. Lee (klee2@opentext.com)
//
//
// Pre-requisites:
// - Fortify ScanCentral SAST has been installed (for Fortify Hosted/on-premise SAST)
// - Fortify ScanCentral DAST has been installed (for Fortify Hosted/on-premise DAST)
// - Fortify Jenkins plugins has been installed and configured (if not using fcli)
// - Docker Jenkins Pipeline plugin has been installed
// - [Optional] Debricked account
// - [Optional] Sonatype Nexus IQ server has been installed for OSS SCA vulnerabilities
//
// Typical node setup:
// - Create a new Jenkins agent (or reuse one) for running Fortify Commands
// - Install Fortify ScanCentral Client on the agent machine
// - Install Fortify CLI (fcli) tool on the agent machine and add to system/agent path
// - Apply the label "fortify" to the agent.
// - Set the environment variable "FORTIFY_HOME" on the agent to point to the location of the Fortify ScanCentral Client installation
//
// Credentials setup:
// Create the following redentials in Jenkins and enter values as follows:
//		iwa-git-auth-id		        - Git login as Jenkins "Username with Password" credential
//      iwa-ssc-ci-token-id         - Fortify Software Security Center "CIToken" authentication token as Jenkins Secret credential
//      iwa-debricked-token-id      - Debricked API access token as Jenkins Secret credential
//      iwa-nexus-iq-token-id       - Sonatype Nexus IQ user token as Jenkins Secret credential in form of "user code:pass code"
// Note: All of the credentials should be created (with empty values if necessary) even if you are not using the capabilities.
//
//****************************************************************************************************

// The instances of Docker image and container that are created
def dockerImage
def dockerContainer
def dockerContainerName = "iwa-jenkins"
def dastScanName = "iwa-jenkins"

pipeline {
    agent any

    //
    // The following parameters can be selected when the pipeline is executed manually to execute
    // different capabilities in the pipeline or configure the servers that are used.

    // Note: the pipeline needs to be executed at least once for the parameters to be available
    //
    parameters {
        booleanParam(name: 'SCANCENTRAL_SAST', 	defaultValue: params.SCANCENTRAL_SAST ?: false,
                description: 'Run a remote scan using Scan Central SAST (SCA) for Static Application Security Testing')
        booleanParam(name: 'SCANCENTRAL_DAST', 	defaultValue: params.SCANCENTRAL_DAST ?: false,
                description: 'Run a remote scan using Scan Central DAST (WebInspect) for Dynamic Application Security Testing')
        booleanParam(name: 'SONATYPE_SCA',      defaultValue: params.SONATYPE_SCA ?: false,
                description: 'Use Sonatype Nexus IQ for Open Source Software Composition Analysis')
        booleanParam(name: 'DEBRICKED_SCA',      defaultValue: params.DEBRICKED_SCA ?: false,
                description: 'Use Debricked for Open Source Software Composition Analysis')
        booleanParam(name: 'UPLOAD_TO_SSC',		defaultValue: params.UPLOAD_TO_SSC ?: false,
                description: 'Enable upload of scan results to Fortify Software Security Center')
        booleanParam(name: 'USE_DOCKER', defaultValue: params.USE_DOCKER ?: false,
                description: 'Package the application into a Dockerfile for running/testing')
        booleanParam(name: 'RELEASE_TO_GITHUB', defaultValue: params.RELEASE_TO_GITHUB ?: false,
                description: 'Release built and tested image to GitHub packages')
    }

    environment {
        // Application settings
        COMPONENT_NAME = "iwa"                              // Short form component name
        COMPONENT_VERSION = "1.0"                           // Short form component version
        DOCKER_IMAGE_NAME = "iwa"                           // Docker image name
        DOCKER_IMAGE_VER = "1.0-build"                      // Docker image version
        GIT_URL = scm.getUserRemoteConfigs()[0].getUrl()    // Git Repo
        JAVA_VERSION = 11                                   // Java version to compile as

        // Credential references
        GIT_CREDS = credentials('iwa-git-auth-id')
        SSC_CI_TOKEN = credentials('iwa-ssc-ci-token-id')
        NEXUS_IQ_AUTH_TOKEN = credentials('iwa-nexus-iq-token-id')
        DEBRICKED_TOKEN = credentials('iwa-debricked-token-id')

        // The following are defaulted and can be overriden by creating a "Build parameter" of the same name
        // You can update this Jenkinsfile and set defaults here for internal pipelines
        APP_URL = "${params.APP_URL ?: 'https://iwa.onfortify.com'}" // URL of application to be tested by ScanCentral DAST
        SSC_URL = "${params.SSC_URL ?: 'https://ssc.onfortify.com'}" // URL of Fortify Software Security Center
        SSC_APP_NAME = "${params.SSC_APP_NAME ?: 'IWA'}" // Name of Application in SSC to upload results to
        SSC_APP_VERSION = "${params.SSC_APP_VERSION ?: 'jenkins-ci'}" // Name of Application Version in SSC to upload results to
        SSC_FILTERSETS = "${params.SSC_FILTERSETS ?: 'Quick View'}" // Name of Application Version Filter Sets to use for generating summary reports
        SSC_NOTIFY_EMAIL = "${params.SSC_NOTIFY_EMAIL ?: 'do-not-reply@microfocus.com'}" // User to notify with SSC/ScanCentral information
        SSC_SENSOR_POOL_UUID = "${params.SSC_SENSOR_POOL_UUID ?: '00000000-0000-0000-0000-000000000002'}" // UUID of Scan Central SAST Sensor Pool to use - leave for Default Pool
        SSC_SENSOR_VER = "${params.SSC_SENSOR_VER ?: '24.2'}" // ScanCentral SAST Sensor version
        SCAN_POLICY = "${params.SCAN_POLICY ?: 'devops'}"  // Scan Policy to use (see documentation for details)
        SCANCENTRAL_SAST_CLIENT_AUTH_TOKEN = "${params.SCANCENTRAL_SAST_CLIENT_AUTH_TOKEN ?: 'FortifyDemo'}" // ScanCentral SAST Client Authentication Token
        SCANCENTRAL_DAST_URL = "${params.SCANCENTRAL_DAST_URL ?: 'https://scancentral-dast-api.onfortify.com/swagger/index.html'}" // ScanCentral DAST API URI
        SCANCENTRAL_DAST_CICD = "${params.SCANCENTRAL_DAST_CICD ?: 'a93289b9-2d62-4270-9011-2f573d74b156'}" // ScanCentral DAST CICD identifier
        NEXUS_IQ_APP_ID = "${params.NEXUS_IQ_APP_ID ?: 'IWA'}" // Sonatype Nexus IQ App Id
        DEBRICKED_APP_ID = "${params.DEBRICKED_APP_ID ?: 'jenkins/IWA'}" // Debricked App Id
        DOCKER_OWNER = "${params.DOCKER_OWNER ?: 'fortify-presales'}" // Docker owner (in GitHub packages) to push released images to
    }

    //tools {
    //
    //}

    stages {
        stage('Setup') {
            agent any
            steps {
                script {
                    sh """
                        fcli --version
                        fcli tool sc-client install -t "${env.SCANCENTRAL_SAST_CLIENT_AUTH_TOKEN}"
                        export PATH="$PATH:$HOME/fortify/tools/bin"
                    """
                }
            }
        }
        stage('Build') {
            agent any
            steps {

                script {
                    // Retrieve latest Git commit id
                    if (isUnix()) {
                        sh 'git rev-parse HEAD > .git/commit-id'
                    } else {
                        bat(/git rev-parse HEAD > .git\\commit-id/)
                    }
                    env.GIT_COMMIT_ID = readFile('.git/commit-id').trim()
                    echo "Git commit id: ${env.GIT_COMMIT_ID}"

                    // Run gradle to build application
                    if (isUnix()) {
                        sh './gradlew clean build'
                    } else {
                        bat ".\\gradlew.bat clean build"
                    }
                }
            }

            post {
                success {
                    // Record the test results (success)
                    junit "**/build/test-results/test/TEST-*.xml"
                    // Archive the built file
                    archiveArtifacts "build/libs/${env.COMPONENT_NAME}-${env.COMPONENT_VERSION}.jar"
                    // Stash the deployable files
                    stash includes: "build/libs/${env.COMPONENT_NAME}-${env.COMPONENT_VERSION}.jar", name: "${env.COMPONENT_NAME}_release"
                }
                failure {
                    script {
                        if (fileExists('build/test-results/test')) {
                            junit "**/build/test-results/test/TEST-*.xml"
                        }
                    }
                }
            }
        }

        stage('SAST') {
            when {
                beforeAgent true
                anyOf {
                    expression { params.SCANCENTRAL_SAST == true }
                }
            }
            // Run on an Agent with "fortify" label applied
            agent {label "fortify"}
            steps {
                script {
                    if (params.SCANCENTRAL_SAST) {

                        // comment out below to use Fortify Jenkins Plugin

                        def uploadArg = (params.UPLOAD_TO_SSC ? "--publish-to ${env.SSC_APP_NAME}:${env.SSC_APP_VERSION}" : "")
                        sh """
                            fcli tool sc-client install -t "${env.SCANCENTRAL_SAST_CLIENT_AUTH_TOKEN}"
                            export PATH="$PATH:$HOME/fortify/tools/bin"
                            fcli sc-sast session login --ssc-url ${env.SSC_URL} --ssc-ci-token ${SSC_CI_TOKEN} --client-auth-token "${env.SCANCENTRAL_SAST_CLIENT_AUTH_TOKEN}" --session jenkins
                            scancentral package -bt gradle -bf build.gradle -o Package.zip
                            fcli sc-sast scan start --sensor-version ${env.SSC_SENSOR_VER} ${uploadArg} -p Package.zip --store curScan --session jenkins
                            fcli sc-sast scan wait-for ::curScan:: --session jenkins
                        """
                       
                        // uncomment below to use Fortify Jenkins Plugin

                        // Set Remote Analysis options
                        //def transOptions = '"-exclude \"**/Test/*.java\""'
                        //def scanOptions = '"-scan-policy '.concat("${env.SCAN_POLICY}").concat('"')
                        //fortifyRemoteArguments transOptions: "${transOptions}", scanOptions: "${scanOptions}"
                        //
                        //if (params.UPLOAD_TO_SSC) {
                            // Remote analysis (using Scan Central) with upload to SSC
                        //    fortifyRemoteAnalysis remoteAnalysisProjectType: fortifyGradle(buildFile: 'build.gradle', skipBuild: false),
                        //            remoteOptionalConfig: [
                        //                    customRulepacks: "${env.WORKSPACE}" + "/etc/example-custom-rules.xml",
                        //                    filterFile     : "${env.WORKSPACE}" + "/etc/example-filter.txt",
                        //                    notifyEmail    : "${env.SSC_NOTIFY_EMAIL}",
                        //                    sensorPoolUUID : "${env.SSC_SENSOR_POOL_UUID}"
                        //            ],
                        //            uploadSSC: [
                        //                    appName   : "${env.SSC_APP_NAME}",
                        //                    appVersion: "${env.SSC_APP_VERSION}"
                        //            ]
                        //} else {
                            // Remote analysis (using Scan Central)
                        //    fortifyRemoteAnalysis remoteAnalysisProjectType: fortifyGradle(buildFile: 'build.gradle', skipBuild: false),
                        //            remoteOptionalConfig: [
                        //                    customRulepacks: "${env.WORKSPACE}" + "/etc/example-custom-rules.xml",
                        //                    filterFile     : "${env.WORKSPACE}" + "/etc/example-filter.txt",
                        //                    notifyEmail   : "${env.SSC_NOTIFY_EMAIL}",
                        //                    sensorPoolUUID: "${env.SSC_SENSOR_POOL_UUID}"
                        //            ]
                        //}
                        

                    } else {
                        echo "No Static Application Security Testing (SAST) to do."
                    }
                }
            }
        }

        stage('SCA OSS') {
            when {
                beforeAgent true
                anyOf {
                    expression { params.SONATYPE_SCA == true || params.DEBRICKED_SCA == true }
                }
            }
            agent any
            steps {
                script {
                    if (params.SONATYPE_SCA) {
                        nexusPolicyEvaluation advancedProperties: '',
                            enableDebugLogging: false,
                            failBuildOnNetworkError: true,
                            iqApplication: selectedApplication("${NEXUS_IQ_APP_ID}"),
                            iqModuleExcludes: [[moduleExclude: 'build/**/*test*.*']],
                            iqScanPatterns: [[scanPattern: 'build/**/*.jar']],
                            iqStage: 'build',
                            jobCredentialsId: ''
                    } else if (params.DEBRICKED_SCA) {
                        docker.image('debricked/debricked-cli').inside('--entrypoint="" -v ${WORKSPACE}:/data -w /data') {
                            sh "/home/entrypoint.sh debricked:scan '' ${env.DEBRICKED_TOKEN} ${env.DEBRICKED_APP_ID} ${env.GIT_COMMIT_ID} null cli"
                        }
                    } else {
                        echo "No Software Composition Analysis to do."
                    }

                }
            }
        }

        stage('Deploy') {
            agent any
            steps {
                script {
                    // unstash the built files
                    unstash name: "${env.COMPONENT_NAME}_release"
                    if (isUnix()) {
                        // Create docker image using JAR file
                        if (params.USE_DOCKER) {
                            dockerImage = docker.build("${env.DOCKER_OWNER}/${env.DOCKER_IMAGE_NAME}:${env.DOCKER_IMAGE_VER}.${env.BUILD_NUMBER}", "-f Dockerfile .")
                        }
                    } else {
                        // Create docker image using JAR file
                        if (params.USE_DOCKER) {
                            dockerImage = docker.build("${env.DOCKER_OWNER}/${env.DOCKER_IMAGE_NAME}:${env.DOCKER_IMAGE_VER}.${env.BUILD_NUMBER}", "-f Dockerfile.win .")
                        }
                    }
                }
            }
        }

        stage('DAST') {
            when {
                beforeAgent true
                anyOf {
                    expression { params.SCANCENTRAL_DAST == true }
                }
            }
            steps {
                script {
                    if (params.SCANCENTRAL_DAST) {
                        if (params.USE_DOCKER) {
                            // check if container is still running and if so stop/remove it
                            sh(script: "docker ps -aq --filter name=${dockerContainerName} > container.id")
                            if (fileExists('container.id')) {
                                def existingId = readFile('container.id').trim()
                                if (existingId) {
                                    echo "Found existing ${dockerContainerName} container id: ${existingId} ... deleting..."
                                    sh(script: "docker stop $existingId && docker rm -f $existingId")
                                }
                            }

                            // start docker container
                            echo "Starting docker container ${dockerContainerName}"
                            dockerContainer = dockerImage.run("--name ${dockerContainerName} -p 9090:8080")
                        }

                        sh """
                            fcli sc-dast session login --ssc-url ${env.SSC_URL} --ssc-ci-token ${SSC_CI_TOKEN} --session jenkins
                            fcli sc-dast scan start --name '${dastScanName}' --settings ${env.SCANCENTRAL_DAST_CICD} --store curScan --session jenkins
                            fcli sc-dast scan wait-for ::curScan:: -i 30s -t 6h --session jenkins
                        """


                    } else {
                        echo "No Dynamic Application Security Testing (DAST) to do."
                    }
                }
            }
        }

        // An example release gate/checkpoint
        stage('Gate') {
            agent any
            steps {
                script {
                    sh """
                        fcli ssc session login --url ${env.SSC_URL} --ci-token ${SSC_CI_TOKEN} --session jenkins
                        fcli ssc action run check-policy --appversion ${env.SSC_APP_NAME}:${env.SSC_APP_VERSION} --session jenkins
                    """
                    //input id: 'Release',
                    //        message: 'Ready to Release?',
                    //        ok: 'Yes, let\'s go',
                    //        submitter: 'admin',
                    //        submitterParameter: 'approver'
                }
            }
        }

        stage('Release') {
            agent any
            steps {
                script {
                    // Example publish to GitHub packages
                    if (params.RELEASE_TO_GITHUB) {
                        docker.withRegistry('https://ghcr.io', 'iwa-git-auth-id') {
                            dockerImage.push("${env.DOCKER_IMAGE_VER}.${BUILD_NUMBER}")
                            // and tag as "latest"
                            dockerImage.push("latest")
                        }
                    } else {
                        echo "No releasing to do."
                    }
                }
            }
        }

    }

    post {
        always {
            script {
                // run summary report and logout
                sh """
                    fcli ssc session login --url ${env.SSC_URL} --ci-token ${SSC_CI_TOKEN} --session jenkins
                    fcli ssc action run appversion-summary --appversion ${env.SSC_APP_NAME}:${env.SSC_APP_VERSION} --filtersets "${env.SSC_FILTERSETS}" --session jenkins
                    fcli sc-sast session logout --session jenkins
                """
                // check if container is still running and if so stop/remove it
                if (params.USE_DOCKER) {
                    if (isUnix()) {
                        sh(script: "docker ps -aq --filter name=${dockerContainerName} > container.id")
                        if (fileExists('container.id')) {
                            def existingId = readFile('container.id').trim()
                            if (existingId) {
                                echo "Found existing ${dockerContainerName} container id: ${existingId} ... deleting..."
                                sh(script: "docker stop $existingId && docker rm -f $existingId")
                            }
                        }
                    } else {
                        bat(script: "docker ps -aq --filter name=${dockerContainerName} > container.id")
                        if (fileExists('container.id')) {
                            def existingId = readFile('container.id').trim()
                            if (existingId) {
                                echo "Found existing ${dockerContainerName} container id: ${existingId} ... deleting..."
                                bat(script: "docker stop ${existingId} && docker rm -f ${existingId}")
                            }
                        }
                    }
                }
            }
        }
    }

}
