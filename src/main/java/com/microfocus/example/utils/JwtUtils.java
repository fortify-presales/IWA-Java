/*
        Insecure Web App (IWA)

        Copyright (C) 2020-2022 Micro Focus or one of its affiliates

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

package com.microfocus.example.utils;

import java.time.Instant;
import java.util.Date;

import com.microfocus.example.entity.CustomUserDetails;
import com.microfocus.example.entity.User;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

import io.jsonwebtoken.*;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;

@Component
public class JwtUtils {
    private static final Logger log = LoggerFactory.getLogger(JwtUtils.class);

    @Value("${spring.jwt.secret:eLgvVuw3qIHLNGNH/XNASMiV1RQlVgNakeDsLu7svKQP7jtu2+35wwu/rfwBAQi88wCiuCU66NS66BEySj6jQ4tLOJy4Jn5USbjBk98vMYnT+3me2lYqTUg/tdEg2HHMzhnu+MOXdq5LK1iwr0/uTob/meDy2cIT3ljF+8L7ZuxnwYYW0BTQsM+0nDTYNg4Ik/ChORRBjDyNpplzGvJlqvY5g2RkCyIP0WRe1A==}")
    private String jwtSecret;

    @Value("#{new Integer(${spring.jwt.expiration-ms:0})}")
    private int jwtExpirationMs;

    @Value("#{new Integer(${spring.jwt.refresh-ms:0})}")
    private int jwtRefreshMs;

    public String generateJwtToken(Authentication authentication) {
        CustomUserDetails userPrincipal = (CustomUserDetails) authentication.getPrincipal();
        return generateJwtTokenFromUsername(userPrincipal.getUsername());
    }

    public String generateJwtTokenFromUsername(String username) {
        log.debug("JwtUtils::generateJwtTokenFromUsername for: {}", username);
        return Jwts.builder()
                .setSubject(username)
                .setIssuedAt(new Date())
                .setExpiration(new Date((new Date()).getTime() + jwtExpirationMs))
                .signWith(SignatureAlgorithm.HS512, jwtSecret)
                .compact();
    }

    public String generateJwtTokenFromUserDetails(Authentication authentication) {
        log.debug("JwtUtils::generateJwtTokenFromUserDetails for: {}", authentication.toString());
        CustomUserDetails userPrincipal = (CustomUserDetails) authentication.getPrincipal();
        return Jwts.builder()
                .setSubject((userPrincipal.getUsername()))
                .setIssuedAt(new Date())
                .setExpiration(new Date((new Date()).getTime() + jwtRefreshMs))
                .signWith(SignatureAlgorithm.HS512, jwtSecret)
                .compact();
    }

    public Instant getDefaultExpiration() {
        return Instant.now().plusMillis(jwtRefreshMs);
    }

    public long getExpirationFromJwtToken(String token) {
        return Jwts.parser().setSigningKey(jwtSecret).parseClaimsJws(token).getBody().getExpiration().getTime();
    }

    public String getUserNameFromJwtToken(String token) {
        return Jwts.parser().setSigningKey(jwtSecret).parseClaimsJws(token).getBody().getSubject();
    }

    public boolean validateJwtToken(String authToken) {
        try {
            Jwts.parser().setSigningKey(jwtSecret).parseClaimsJws(authToken);
            return true;
        } catch (SignatureException e) {
            log.error("Invalid JWT signature: {}", e.getMessage());
        } catch (MalformedJwtException e) {
            log.error("Invalid JWT token: {}", e.getMessage());
        } catch (ExpiredJwtException e) {
            log.error("JWT token is expired: {}", e.getMessage());
        } catch (UnsupportedJwtException e) {
            log.error("JWT token is unsupported: {}", e.getMessage());
        } catch (IllegalArgumentException e) {
            log.error("JWT claims string is empty: {}", e.getMessage());
        }

        return false;
    }

    public String generateAndSetSession(HttpServletRequest request, HttpServletResponse response,
                                        Authentication authentication) {
        HttpSession session = request.getSession(false);
        CustomUserDetails customUserDetails = (CustomUserDetails) authentication.getPrincipal();
        User user = customUserDetails.getUserDetails();
        String jwtToken = generateJwtToken(authentication);
        log.debug("Generated jwtToken: " + jwtToken);
        session.setAttribute("userId", user.getId());
        session.setAttribute("username", user.getUsername());
        session.setAttribute("authorities", authentication.getAuthorities());
        session.setAttribute("jwtToken", jwtToken);
        return jwtToken;
    }
}
