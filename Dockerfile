FROM eclipse-temurin:17
# A JDK 1.8 is needed if the WebInspect Runtime Agent is being used
#FROM openjdk:8u342-jdk-slim

LABEL maintainer="info@opentext.com"

# Add a volume pointing to /tmp
VOLUME /tmp

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Location of WebInspect RuntTime Agent - uncomment if required
#ARG WI_AGENT_DIR=/installs/Fortify_WebInspect_Runtime_Agent_Java/

# The application's jar file
ARG JAR_FILE=build/libs/iwa-1.0.jar

# Copy Fortify WebInspect Runtime Agent directory to the container - uncomment if required
#COPY ${WI_AGENT_DIR} /wirtagent

# Use a working directory so files are located at /app inside the image
WORKDIR /app

# Copy the application's jar to the container (will become /app/app.jar)
COPY ${JAR_FILE} app.jar

# Copy the entrypoint script and make it executable
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# JAVA_OPTS to be passed in (can be overridden at runtime)
# also fix spring profiles property name (spring.profiles.active)
ENV JAVA_OPTS="-Xmx512m -Xss256k -Dspring.profiles.active=default"

# Healthcheck defaults (can be overridden at runtime)
ENV HEALTHCHECK_PATH="/actuator/health"
ENV HEALTHCHECK_PORT="8080"
ENV HEALTHCHECK_INTERVAL="30s"
ENV HEALTHCHECK_TIMEOUT="5s"
ENV HEALTHCHECK_START_PERIOD="10s"
ENV HEALTHCHECK_RETRIES="3"

# Ensure curl is available in the image for the healthcheck
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Docker HEALTHCHECK: probe the Spring Boot actuator health endpoint
# Use literal durations in the HEALTHCHECK flags (Dockerfile does not support variable substitution in these flags at parse time)
# Replaced HTTP probe with a lightweight TCP probe so the healthcheck doesn't require the actuator endpoint to be public or unauthenticated.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD bash -c "</dev/tcp/127.0.0.1/${HEALTHCHECK_PORT}" || exit 1

# Notes:
# - Pass runtime configuration such as SPRING_MAIL_HOST, SPRING_MAIL_PASSWORD, etc. as environment variables
#   when running the container (docker run -e SPRING_MAIL_HOST=...).
# - For App Service / Kubernetes / Azure, set the same env var names in the platform's configuration UI.

# Use the entrypoint script so we only wait for mail when configured
ENTRYPOINT ["/app/docker-entrypoint.sh"]
