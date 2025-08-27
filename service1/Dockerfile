FROM amazoncorretto:17-alpine3.18
WORKDIR /app
COPY target/com.service1-3.1.5-shaded.jar app.jar
EXPOSE 8080
#, "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005"
ENTRYPOINT ["java", "-jar", "app.jar"]