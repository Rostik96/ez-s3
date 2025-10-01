package dev.rost.ezs3;

import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;

import java.io.File;

/**
 * Sets Java SSL system properties for AWS SDK auto-configuration.
 * This provides the same declarative SSL configuration as Spring Kafka
 * by leveraging Java's built-in SSL system properties.
 */
@Slf4j
@Configuration
@ConditionalOnProperty(name = "spring.cloud.aws.s3.ssl.trust-store-location")
class S3SslPropertiesConfig {

    @Value("${spring.cloud.aws.s3.ssl.trust-store-type}")
    private String trustStoreType;

    @Value("${spring.cloud.aws.s3.ssl.trust-store-location}")
    private File trustStore;

    @Value("${spring.cloud.aws.s3.ssl.trust-store-password}")
    private String trustStorePassword;


    @Value("${spring.cloud.aws.s3.ssl.key-store-type}")
    private String keyStoreType;

    @Value("${spring.cloud.aws.s3.ssl.key-store-location}")
    private File keyStore;

    @Value("${spring.cloud.aws.s3.ssl.key-store-password}")
    private String keyStorePassword;


    @PostConstruct
    public void configureSslSystemProperties() {
        log.info("Configuring SSL system properties for AWS SDK auto-configuration");
        
        // Set SSL system properties that AWS SDK will automatically use
        System.setProperty("javax.net.ssl.trustStore", trustStore.getAbsolutePath());
        System.setProperty("javax.net.ssl.trustStorePassword", trustStorePassword);
        System.setProperty("javax.net.ssl.trustStoreType", trustStoreType);
        
        System.setProperty("javax.net.ssl.keyStore", keyStore.getAbsolutePath());
        System.setProperty("javax.net.ssl.keyStorePassword", keyStorePassword);
        System.setProperty("javax.net.ssl.keyStoreType", keyStoreType);
        
        log.info("SSL system properties configured for AWS SDK");
        log.debug("TrustStore: {} (type: {})", trustStore, trustStoreType);
        log.debug("KeyStore: {} (type: {})", keyStore, keyStoreType);
    }
}
