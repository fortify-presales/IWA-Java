package com.microfocus.example.config;

import org.mockito.Mockito;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.mail.javamail.JavaMailSender;

import javax.mail.internet.MimeMessage;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.when;

@Configuration
public class TestMailConfiguration {

    @Bean
    @Primary
    public JavaMailSender javaMailSender() {
        JavaMailSender mailSender = Mockito.mock(JavaMailSender.class);
        MimeMessage mockMessage = Mockito.mock(MimeMessage.class);
        when(mailSender.createMimeMessage()).thenReturn(mockMessage);
        // When send is called with any MimeMessage, do nothing (avoid network)
        doNothing().when(mailSender).send(any(MimeMessage.class));
        return mailSender;
    }
}

