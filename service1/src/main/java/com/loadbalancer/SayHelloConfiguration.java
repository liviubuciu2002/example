package com.loadbalancer;

import com.amazonaws.auth.AWSCredentials;
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.services.servicediscovery.AWSServiceDiscovery;
import com.amazonaws.services.servicediscovery.AWSServiceDiscoveryClientBuilder;
import com.amazonaws.services.servicediscovery.model.DiscoverInstancesRequest;
import com.amazonaws.services.servicediscovery.model.DiscoverInstancesResult;
import org.springframework.cloud.client.DefaultServiceInstance;
import org.springframework.cloud.client.ServiceInstance;
import org.springframework.cloud.loadbalancer.core.ServiceInstanceListSupplier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import reactor.core.publisher.Flux;

import java.util.List;

/**
 * @author Olga Maciaszek-Sharma
 */
public class SayHelloConfiguration {

    @Bean
    @Primary
    ServiceInstanceListSupplier serviceInstanceListSupplier() {
        System.out.println("liviu , inside configuration load balancer");
        return new DemoServiceInstanceListSuppler("service2");
    }

}

class DemoServiceInstanceListSuppler implements ServiceInstanceListSupplier {

    private final String serviceId;

    DemoServiceInstanceListSuppler(String serviceId) {
        this.serviceId = serviceId;
    }

    @Override
    public String getServiceId() {
        return serviceId;
    }

    @Override
    public Flux<List<ServiceInstance>> get() {

        AWSCredentials credentials = new BasicAWSCredentials("", "");

        System.out.format("Liviu : Instances in AWS cloud map %s:\n", "service----------");

        AWSServiceDiscovery client = AWSServiceDiscoveryClientBuilder
                .standard()
                .withCredentials(new AWSStaticCredentialsProvider(credentials))
                .withRegion("us-east-1")
                .build();

        DiscoverInstancesRequest request = new DiscoverInstancesRequest();
        request.setNamespaceName("service2.local");
        request.setServiceName("service2");

        DiscoverInstancesResult result = client.discoverInstances(request);


        return Flux.just(result.getInstances().stream().map(
                        s -> {
                            System.out.println("liviu host ip = " + s.getAttributes().get("AWS_INSTANCE_IPV4"));
                            return (ServiceInstance) new DefaultServiceInstance(s.getInstanceId(), "service2", s.getAttributes().get("AWS_INSTANCE_IPV4"), 8080, false);
                        }).
                toList());
    }
}