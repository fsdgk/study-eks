FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace

COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -q -DskipTests dependency:go-offline

COPY src src
RUN ./mvnw -DskipTests package

FROM eclipse-temurin:21-jre-alpine

RUN addgroup -S petclinic && adduser -S petclinic -G petclinic

WORKDIR /app

COPY --from=build /workspace/target/spring-petclinic-*.jar app.jar

USER petclinic

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
