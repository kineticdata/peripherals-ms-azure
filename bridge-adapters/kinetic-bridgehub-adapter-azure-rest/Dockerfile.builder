# STAGE: builder
FROM maven:3.6-jdk-8 as intermediate

ARG iam_user_access_key_id
ARG iam_user_secret_key

# Prepare the maven dependencies (so it is cached independent from the sources)
WORKDIR /builder
COPY pom.xml pom.xml
COPY docker/maven/settings.xml /root/.m2/settings.xml
RUN mvn install -Diam-user-access-key-id=$iam_user_access_key_id -Diam-user-secret-key=$iam_user_secret_key -Dmaven.test.skip=true

# STAGE: Remove ARGs
FROM maven:3.6-jdk-8

COPY --from=intermediate /root/.m2 /root/.m2

# Set entrypoint
ENTRYPOINT ["mvn", "clean", "install"]