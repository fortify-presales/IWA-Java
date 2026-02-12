#!/usr/bin/env groovy

//****************************************************************************************************
// An example pipeline for DevSecOps using OpenText Fortify Application Security products
// @author: Kevin A. Lee (klee2@opentext.com)
//
//
// Pre-requisites:
// - [Optional] Fortify on Demand Jenkins plugin has been installed and configured (if not using fcli)
// - [Optional] Debricked account
//
// Typical node setup:
// - Create a new Jenkins agent (or reuse one) for running Fortify Commands
// - Install Fortify CLI (fcli) tool on the agent machine and add to system/agent path (default is to download from internet)
//
// Credentials setup:
// Create the following credentials in Jenkins and enter values as follows:
//		iwa-git-auth		        - Git login as Jenkins "Username with Password" credential
//      iwa-fod-client-id           - Fortify on Demand API Client Id as Jenkins Secret credential
//      iwa-fod-client-secret       - Fortify on Demand API Client Secret as Jenkins Secret credential
//      iwa-debricked-token         - Debricked API access token as Jenkins Secret credential
// Note: All of the credentials should be created (with empty values if necessary) even if you are not using the capabilities.
//
//****************************************************************************************************

pipeline {
    agent any

    //
    // The following parameters can be selected when the pipeline is executed manually to execute
    // different capabilities in the pipeline or configure the servers that are used.

    // Note: the pipeline needs to be executed at least once for the parameters to be available
    //
    parameters {
        booleanParam(name: 'FOD_SAST', defaultValue: params.FOD_SAST ?: false,
                description: 'Use Fortify on Demand for Static Application Security Testing')
        booleanParam(name: 'FOD_DAST',	defaultValue: params.FOD_DAST ?: false,
                description: 'Use Fortify on Demand for Dynamic Application Security Testing')
        booleanParam(name: 'DEBRICKED_SCA', defaultValue: params.DEBRICKED_SCA ?: false,
                description: 'Use Debricked for Open Source Software Composition Analysis')
    }

    environment {
        // Application settings
        APP_NAME = "iwa-java"                              // Short form component name
        APP_VERSION = "1.0"                           // Short form component version
        GIT_URL = scm.getUserRemoteConfigs()[0].getUrl()    // Git Repo
        GIT_REPO_NAME = GIT_URL.split('/').last().replace('.git', '') // Git Repo name

        // Credential references
        GIT_CREDS = credentials('iwa-git-auth')
        FOD_CLIENT_ID = credentials('iwa-fod-client-id')
        FOD_CLIENT_SECRET = credentials('iwa-fod-client-secret')
        DEBRICKED_TOKEN = credentials('iwa-debricked-token')

        // The following are defaulted and can be overriden by creating a "Build parameter" of the same name
        // You can update this Jenkinsfile and set defaults here for internal pipelines
        APP_URL = "${params.APP_URL ?: 'https://iwajava.azurewebsites.net'}" // URL of application to be tested by ScanCentral DAST
        FOD_URL = "${params.FOD_URL ?: 'https://api.emea.fortify.com'}" // URL of Fortify on Demand
        FORTIFY_APP_NAME_POSTFIX = "${params.FORTIFY_APP_NAME_POSTFIX ?: ''}" // Fortify on Demand application name postfix
        FOD_RELEASE_ID = "${params.FOD_RELEASE_ID ?: '0'}" // Fortify on Demand release id
   
        // The following are "set" for use in `fcli action run ci`
        GITHUB_SHA = sh (script: "git rev-parse HEAD", returnStdout: true).trim()
        GITHUB_REPOSITORY = "${env.GIT_REPO_NAME}${env.FORTIFY_APP_NAME_POSTFIX}"
        GITHUB_REF_NAME = sh (script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
        GITHUB_BRANCH = "${params.FOD_APPVER_NAME ?: env.GIT_REF_NAME}"
    }  

    //tools {
    //
    //}

    stages {
        stage('Build') {
            agent any
            steps {
                script {
                    // Run gradle to build application
                    sh """
                        ./gradlew clean build
                    """
                }
            }
            post {
                success {
                    // Record the test results (success)
                    junit "**/build/test-results/test/TEST-*.xml"
                    // Archive the built file
                    archiveArtifacts "build/libs/${env.APP_NAME}-${env.APP_VERSION}.jar"
                    // Stash the deployable files
                    stash includes: "build/libs/${env.APP_NAME}-${env.APP_VERSION}.jar", name: "${env.APP_NAME}_release"
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
                    expression { params.FOD_SAST == true }
                }
            }
            agent any
            steps {
                script {
                    if (params.FOD_SAST) {

                        sh """
                            echo "GITHUB_SHA: ${env.GITHUB_SHA}"
                            echo "GITHUB_REPOSITORY: ${env.GITHUB_REPOSITORY}"
                            echo "GITHUB_BRANCH: ${env.GITHUB_BRANCH}"
                            echo "FOD_URL: ${env.FOD_URL}"
                            echo "FOD_CLIENT_ID: ${env.FOD_CLIENT_ID}"
                            echo "FOD_CLIENT_SECRET: ${env.FOD_CLIENT_SECRET}"
                            echo "FOD_RELEASE_ID: ${env.FOD_RELEASE_ID}"
                        """

                        // uncomment below to use fcli
                        // comment out below to use Fortify on Demand Jenkins Plugin
                        sh """
                            curl -L https://github.com/fortify/fcli/releases/download/latest/fcli-linux.tgz | tar -xz fcli
                            export FOD_RELEASE="${env.GITHUB_REPOSITORY}:${env.GITHUB_BRANCH}"
                            ./fcli fod action run ci
                        """
                       
                        // uncomment below to use Fortify on Demand Jenkins Plugin
                        // comment out below to use fcli
                        //fodStaticAssessment releaseId: "${env.FOD_RELEASE_ID}", isMicroservice: false, openSourceScan: 'false',
                        //    inProgressBuildResultType: 'WarnBuild', inProgressScanActionType: 'Queue', remediationScanPreferenceType: 'NonRemediationScanOnly',
                        //    scanCentral: 'Gradle', scanCentralBuildCommand: 'clean build', scanCentralBuildFile: 'build.gradle'
                        //fodPollResults releaseId: "${env.FOD_RELEASE_ID}", policyFailureBuildResultPreference: 1, pollingInterval: 5

                    } else {
                        echo "No Static Application Security Testing (SAST) to do."
                    }
                }
            }
        }

        stage('SCA') {
            when {
                beforeAgent true
                anyOf {
                    expression { params.DEBRICKED_SCA == true }
                }
            }
            agent any
            steps {
                script {
                    if (params.DEBRICKED_SCA) {
                        script {
                            // Inspiration taken from https://github.com/trustin/os-maven-plugin/blob/master/src/main/java/kr/motd/maven/os/Detector.java
                            // Note: exit from 'debricked scan' is ignored - remove '|| true' to fail the pipeline if it fails
                            def osName = System.getProperty("os.name").toLowerCase(Locale.US).replaceAll("[^a-z0-9]+", "")
                            if (osName.startsWith("linux")) { osName = "linux" }
                            else if (osName.startsWith("mac") || osName.startsWith("osx")) { osName = "macOS" }
                            else if (osName.startsWith("windows")) { osName = "windows" }
                            else { osName = "linux" } // Default to linux

                            def osArch = System.getProperty("os.arch").toLowerCase(Locale.US).replaceAll("[^a-z0-9]+", "")
                            if (osArch.matches("(x8664|amd64|ia32e|em64t|x64)")) { osArch = "x86_64" }
                            else if (osArch.matches("(x8632|x86|i[3-6]86|ia32|x32)")) { osArch = "i386" }
                            else if (osArch.matches("(aarch_64)")) { osArch = "arm64" }
                            else { osArch = "x86_64" } // Default to x86 64-bit

                            println("OS detected: " + osName + " and architecture " + osArch)
                            sh 'curl -LsS https://github.com/debricked/cli/releases/download/release-v2/cli_' + osName + '_' + osArch + '.tar.gz | tar -xz debricked'
                            sh './debricked scan || true'
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
                    sh """
                        echo "Simulating deploying the application to a server"
                    """
                }
            }
        }

        stage('DAST') {
            when {
                beforeAgent true
                anyOf {
                    expression { params.FOD_DAST == true }
                }
            }
            steps {
                script {
                    if (params.FOD_DAST) {
                        sh """
                            curl -L https://github.com/fortify/fcli/releases/download/latest/fcli-linux.tgz | tar -xz fcli
                            echo "Running DAST scan against: ${env.APP_URL}"
                            ./fcli fod session login --client-id ${env.FOD_CLIENT_ID} --client-secret ${env.FOD_CLIENT_SECRET} --url ${env.FOD_URL} --fod-session jenkins
                            echo ./fcli fod dast-scan start --release "${env.GITHUB_REPOSITORY}:${env.GITHUB_BRANCH}" --fod-session jenkins --store curScan
                            echo ./fcli fod dast-scan wait-for ::curScan:: --fod-session jenkins
                            ./fcli fod session logout --fod-session jenkins
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
                        curl -L https://github.com/fortify/fcli/releases/download/latest/fcli-linux.tgz | tar -xz fcli
                        echo "Running gate check"
                        ./fcli fod session login --client-id ${env.FOD_CLIENT_ID} --client-secret ${env.FOD_CLIENT_SECRET} --url ${env.FOD_URL} --fod-session jenkins
                        ./fcli fod action run check-policy --release "${env.GITHUB_REPOSITORY}:${env.GITHUB_BRANCH}" --fod-session jenkins
                        ./fcli fod session logout --fod-session jenkins
                    """
                    //input id: 'Release',
                    //        message: 'Ready to Release?',
                    //        ok: 'Yes, let\'s go',
                    //        submitter: 'admin',
                    //        submitterParameter: 'approver'
                }
            }
        }

    }

}
