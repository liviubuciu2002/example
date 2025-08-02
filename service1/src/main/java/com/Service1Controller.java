package com;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;

@RestController
@RequestMapping("/service1")
public class Service1Controller {
    private final WebClient webClient;

    public Service1Controller(WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder.baseUrl("http://service2:8080").build();
    }

    @GetMapping("/call-service2")
    public String callService2() {
//        return

         String responseService2 = webClient.get()
                .uri("/service2/api/data")
                .retrieve()
                .bodyToMono(String.class)
                .block();
         return "Liviu , Service1. " + responseService2;
    }
}