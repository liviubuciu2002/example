package com.liviu;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/service1")
public class Service1Controller {
    private final WebClient.Builder webClient;

    public Service1Controller(WebClient.Builder webClientBuilder) {
        System.out.println("Liviu , servlet rest initialization");
          this.webClient = webClientBuilder;
//        builder.baseUrl("http://localhost:8081");
//        this.webClient = builder.build();
    }

    @GetMapping("/call-service2")
    public Mono<String> callService2() {
        return webClient.build().get()
                .uri("http://service2:8080/service2/api/data")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> "Liviu, Service1. " + response);
    }

    @GetMapping("/call-service")
    public String callService() {
        return "Yupee ! Liviu , Service. ";
    }

}