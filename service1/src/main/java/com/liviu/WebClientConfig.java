package com.liviu;

import com.loadbalancer.SayHelloConfiguration;
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.cloud.loadbalancer.annotation.LoadBalancerClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
@LoadBalancerClient(name = "service2", configuration = SayHelloConfiguration.class)
public class WebClientConfig {

    @LoadBalanced
    @Bean
    public WebClient.Builder webClientBuilder() {
        System.out.println("Liviu : inside web client config");
        return WebClient.builder();
    }

}