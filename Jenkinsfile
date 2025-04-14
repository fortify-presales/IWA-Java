#!/usr/bin/env groovy

//****************************************************************************************************
// An example pipeline for DevSecOps using OpenText Fortify Application Security products
// @author: Kevin A. Lee (klee2@opentext.com)
//
//
// Pre-requisites:
// - Fortify Jenkins plugins has been installed and configured (if not using fcli)
// - Docker Jenkins Pipeline plugin has been installed
// - [Optional] Debricked account
//
// Typical node setup:
// - Create a new Jenkins agent (or reuse one) for running Fortify Commands
// - Install Fortify CLI (fcli) tool on the agent machine and add to system/agent path
// - Apply the label "fortify" to the agent.
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
        booleanParam(name: 'FOD_SAST', defaultValue: params.FOD_SAST ?: false,
                description: 'Use Fortify on Demand for Static Application Security Testing')
        booleanParam(name: 'FOD_DAST',	defaultValue: params.FOD_DAST ?: false,
                description: 'Use Fortify on Demand for Dynamic Application Security Testing')
        booleanParam(name: 'DEBRICKED_SCA', defaultValue: params.DEBRICKED_SCA ?: false,
                description: 'Use Debricked for Open Source Software Composition Analysis')
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
        GIT_CREDS = credentials('iwa-git-auth')
        FOD_CLIENT_ID = credentials('iwa-fod-client-id')
        FOD_CLIENT_SECRET = credentials('iwa-fod-client-secret')
        DEBRICKED_TOKEN = credentials('iwa-debricked-token')

        // The following are defaulted and can be overriden by creating a "Build parameter" of the same name
        // You can update this Jenkinsfile and set defaults here for internal pipelines
        APP_URL = "${params.APP_URL ?: 'https://iwa.onfortify.com'}" // URL of application to be tested by ScanCentral DAST
        FOD_URL = "${params.FOD_URL ?: 'https://api.emea.fortify.com'}" // URL of Fortify on Demand
        FORTIFY_APP_NAME_POSTFIX = "${params.FORTIFY_APP_NAME_POSTFIX ?: ''}" // Fortify on Demand application name postfix
        DOCKER_OWNER = "${params.DOCKER_OWNER ?: 'fortify-presales'}" // Docker owner (in GitHub packages) to push released images to
   
        GITHUB_SHA = sh (script: "git rev-parse HEAD", returnStdout: true).trim()
        //GITHUB_REPOSITORY = "IWA-Java [KAL]" // Hardcoded for testing
        GITHUB_REPOSITORY = sh (script: 'basename `git rev-parse --show-toplevel`', returnStdout: true).trim().concat(" [KAL]") // Hardcoded for testing
        GITHUB_REF_NAME = "jenkins" // Hardcoded for testing
        //GITHUB_REF_NAME = sh (script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
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
                        printenv
                        ./gradlew clean build
                    """
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
        // An example release gate/checkpoint
        stage('Gate') {
            agent any
            steps {
                script {
                    sh """
                        echo "Running gate check"
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
