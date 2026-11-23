package com.moion;

import org.springframework.boot.SpringApplication;

public class TestMoionApplication {

    public static void main(String[] args) {
        SpringApplication.from(MoionApplication::main).with(TestcontainersConfiguration.class).run(args);
    }

}
