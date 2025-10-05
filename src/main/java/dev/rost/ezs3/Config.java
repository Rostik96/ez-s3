package dev.rost.ezs3;

import io.awspring.cloud.autoconfigure.s3.S3ClientCustomizer;
import io.awspring.cloud.s3.S3ProtocolResolver;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.boot.ssl.SslManagerBundle;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import software.amazon.awssdk.http.apache.ApacheHttpClient;

@Configuration
class Config implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    @Bean
    S3ClientCustomizer s3ClientCustomizer(@Value("#{sslBundleRegistry.getBundle('s3').managers}") SslManagerBundle managers) {
        return s3Client ->
                s3Client.httpClient(ApacheHttpClient.builder()
                        .tlsTrustManagersProvider(managers::getTrustManagers)
                        .tlsKeyManagersProvider(managers::getKeyManagers)
                        .build());
    }



    /**
     * Fixes greediness {@link S3ProtocolResolver} that breaks SSL resource loading.
     * Replaces the default resolver with a protocol-aware version that only handles "s3://" URLs.
     * This prevents circular dependencies during SSL bundle initialization when {@link #s3ClientCustomizer loading}
     * truststore/keystore files from classpath.
     */
    @Override
    public void initialize(ConfigurableApplicationContext appCtx) {
        appCtx.addBeanFactoryPostProcessor(beanFactory ->
                ((DefaultListableBeanFactory) beanFactory).getBeanPostProcessors().addFirst(new BeanPostProcessor() {
                    @Override
                    @SuppressWarnings({"NullableProblems", "DataFlowIssue"})
                    public Object postProcessBeforeInitialization(Object bean, String __) {
                        if (bean instanceof S3ProtocolResolver)
                            return new S3ProtocolResolver() {
                                @Override
                                public Resource resolve(String location, ResourceLoader resourceLoader) {
                                    if (!location.startsWith("s3://"))
                                        return null;
                                    return super.resolve(location, resourceLoader);
                                }
                            };
                        return bean;
                    }
                }));
    }
}
