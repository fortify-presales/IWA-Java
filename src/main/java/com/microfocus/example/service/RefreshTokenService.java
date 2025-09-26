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

package com.microfocus.example.service;

import com.microfocus.example.entity.RefreshToken;
import com.microfocus.example.exception.api.ApiRefreshTokenException;
import com.microfocus.example.repository.RefreshTokenRepository;
import com.microfocus.example.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Refresh Token Service to hide business logic / database persistence for Refresh Tokens
 * @author Kevin A. Lee
 */
@Service
@Transactional
public class RefreshTokenService {

    private final Logger log = LoggerFactory.getLogger(getClass());
    private final String SERVICE_NAME = getClass().getName();

    @Value("#{new Integer(${spring.jwt.refresh-ms:0})}")
    private int jwtRefreshMs;

    @Autowired
    private RefreshTokenRepository refreshTokenRepository;

    @Autowired
    private UserRepository userRepository;

    public Optional<RefreshToken> findByToken(String token) {
        return refreshTokenRepository.findById(UUID.fromString(token));
    }

    public RefreshToken createRefreshToken(UUID userId) {
        RefreshToken refreshToken = new RefreshToken();

        refreshToken.setUser(userRepository.findById(userId).get());
        refreshToken.setExpiryDate(Instant.now().plusMillis(jwtRefreshMs));
        refreshToken.setId(UUID.randomUUID());

        refreshToken = refreshTokenRepository.save(refreshToken);
        return refreshToken;
    }

    public RefreshToken verifyExpiration(RefreshToken refreshToken) {
        if (refreshToken.getExpiryDate().compareTo(Instant.now()) < 0) {
            refreshTokenRepository.delete(refreshToken);
            throw new ApiRefreshTokenException(refreshToken.getId().toString(), "Refresh token is expired - please sign-in again!");
        }

        return refreshToken;
    }

    public int deleteByUserId(UUID userId) {
        return refreshTokenRepository.deleteByUser((userRepository.findById(userId).get()));
    }
}
