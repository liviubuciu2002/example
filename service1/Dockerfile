FROM amazoncorretto:17-alpine3.18
WORKDIR /app
COPY target/service1-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]