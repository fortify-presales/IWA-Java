include ./lib/makefile-gradle.defs
-include .env

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

PROJECT := IWA-Java

SAST_TRANSLATE_OPTS := -verbose -debug -exclude "bin" -exclude "etc" -exclude "tests" .
