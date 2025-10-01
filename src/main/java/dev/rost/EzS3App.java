package dev.rost;

import io.awspring.cloud.s3.S3Template;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.context.annotation.Bean;

@SpringBootApplication(scanBasePackages = "dev.rost.ezs3")
public class EzS3App {

	public static void main(String[] args) {
		SpringApplication.run(EzS3App.class, args);
	}


    @Bean
    ApplicationListener<ApplicationReadyEvent> onStartup(S3Template s3Template) {
        return event -> {
            System.out.println("EzS3App#onStartup");
            System.out.println("s3Template.bucketExists(\"ez\") = " + s3Template.bucketExists("ezb"));
        };
    }
}
