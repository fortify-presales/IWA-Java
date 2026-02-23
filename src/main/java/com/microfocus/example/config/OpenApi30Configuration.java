/*
        Insecure Web App (IWA)

        Copyright (C) 2020-2026 Micro Focus or one of its affiliates

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.

        You should have received a copy of the GNU General Public License
        along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

package com.microfocus.example.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeIn;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.servers.Server;
import io.swagger.v3.oas.annotations.servers.ServerVariable;
import org.springframework.context.annotation.Configuration;

@Configuration
@OpenAPIDefinition(info = @Info(
        title = "Insecure Web App (IWA) API",
        description = "This is the REST API for Insecure Web App (IWA) Pharmacy Direct. You can select a development or production server to test the API. " +
                "Most operations require authentication via a user specific JWT token. To retrieve a JWT token for a user you can use the " +
                "Site '/api/v3/site/sign-in' operation below and then copy the value of the 'accessToken' field. This value can then be " +
                "entered when you click on the 'Authorize' button or lock icons.",
        version = "v3"),
        servers = @Server(
                url = "{protocol}://{environment}",
                variables = {
                    @ServerVariable(
                            name = "protocol",
                            allowableValues = {"http","https"},
                            defaultValue = "https"),
                    @ServerVariable(
                            name = "environment",
                            allowableValues = {"localhost:8888", "iwa.onfortify.com"},
                            defaultValue = "iwa.onfortify.com"
                    )
                }
        )
)
/*@SecurityScheme(
        name = "basicAuth",
        type = SecuritySchemeType.HTTP,
        scheme = "basic"
)*/
@SecurityScheme(
        name = "JWT Authentication",
        description = "Type into the textbox: {your JWT token}.",
        type = SecuritySchemeType.HTTP,
        bearerFormat = "JWT",
        in = SecuritySchemeIn.HEADER,
        scheme = "bearer"
)
public class OpenApi30Configuration {

}
