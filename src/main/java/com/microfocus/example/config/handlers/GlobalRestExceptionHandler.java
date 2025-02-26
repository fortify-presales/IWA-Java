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

package com.microfocus.example.config.handlers;

import com.microfocus.example.exception.*;
import com.microfocus.example.exception.api.ApiBadCredentialsException;
import com.microfocus.example.payload.response.ApiStatusResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.TypeMismatchException;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.validation.ObjectError;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import javax.validation.ConstraintViolation;
import javax.validation.ConstraintViolationException;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

@RestControllerAdvice
@Order(value = Ordered.HIGHEST_PRECEDENCE)
public class GlobalRestExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalRestExceptionHandler.class);

    // Custom exception handlers

    @ExceptionHandler(ApiBadCredentialsException.class)
    public ResponseEntity<ApiStatusResponse> badCredentials(final ApiBadCredentialsException ex, final WebRequest request) {
        log.debug("GlobalRestExceptionHandler::badCredentials");
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.NOT_FOUND);
    }

    @ExceptionHandler(UserNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ResponseEntity<ApiStatusResponse> userNotFound(final UserNotFoundException ex, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.NOT_FOUND);
    }

    @ExceptionHandler(RoleNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ResponseEntity<ApiStatusResponse> roleNotFound(final RoleNotFoundException ex, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.NOT_FOUND);
    }

    @ExceptionHandler(MessageNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ResponseEntity<ApiStatusResponse> messageNotFound(final MessageNotFoundException ex, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.NOT_FOUND);
    }

    @ExceptionHandler(ProductNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ResponseEntity<ApiStatusResponse> productNotFound(final ProductNotFoundException ex, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.NOT_FOUND);
    }

    // Generic HTTP exception handlers

    // 400

    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(final MethodArgumentNotValidException ex,
                                                                  final HttpHeaders headers, final HttpStatus status,
                                                                  final WebRequest request) {

        HttpHeaders httpHeader = new HttpHeaders();
        List<MediaType> acceptHeader = MediaType.parseMediaTypes(Arrays.asList(request.getHeaderValues(HttpHeaders.ACCEPT)));

        ArrayList<String> errors = new ArrayList<>();
        for (final FieldError error : ex.getBindingResult().getFieldErrors()) {
            errors.add(error.getField() + ": " + error.getDefaultMessage());
        }
        for (final ObjectError error : ex.getBindingResult().getGlobalErrors()) {
            errors.add(error.getObjectName() + ": " + error.getDefaultMessage());
        }

        if (acceptHeader.stream().anyMatch(mediaType -> mediaType.isCompatibleWith(MediaType.APPLICATION_JSON))) {
             httpHeader.setContentType(MediaType.APPLICATION_JSON);
             final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                     .ApiResponseBuilder()
                     .withSuccess(false)
                     .atTime(LocalDateTime.now(ZoneOffset.UTC))
                     .withErrors(errors)
                     .build();
             ResponseEntity<ApiStatusResponse> apiError = new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.BAD_REQUEST);
             return handleExceptionInternal(ex, apiError, headers, HttpStatus.BAD_REQUEST, request);
        } else if (acceptHeader.stream().anyMatch(mediaType -> mediaType.isCompatibleWith(MediaType.TEXT_PLAIN))) {
             httpHeader.setContentType(MediaType.TEXT_PLAIN);
             return new ResponseEntity<>(errors.toString(), httpHeader, status);
        } else {
             return ResponseEntity.status(status).body(null);
        }
}

    @Override
    protected ResponseEntity<Object> handleBindException(final BindException ex, final HttpHeaders headers,
                                                         final HttpStatus status, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        for (final FieldError error : ex.getBindingResult().getFieldErrors()) {
            errors.add(error.getField() + ": " + error.getDefaultMessage());
        }
        for (final ObjectError error : ex.getBindingResult().getGlobalErrors()) {
            errors.add(error.getObjectName() + ": " + error.getDefaultMessage());
        }
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        ResponseEntity<ApiStatusResponse> apiError = new ResponseEntity<ApiStatusResponse>(apiStatusResponse, HttpStatus.BAD_REQUEST);
        return handleExceptionInternal(ex, apiError, headers, HttpStatus.BAD_REQUEST, request);
    }

    @Override
    protected ResponseEntity<Object> handleTypeMismatch(final TypeMismatchException ex, final HttpHeaders headers,
                                                        final HttpStatus status, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final String error = ex.getValue() + " value for " + ex.getPropertyName() + " should be of type " + ex.getRequiredType();
        errors.add(error);
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<>(apiStatusResponse, new HttpHeaders(), HttpStatus.BAD_REQUEST);
    }

    @Override
    protected ResponseEntity<Object> handleMissingServletRequestPart(final MissingServletRequestPartException ex,
                                                                     final HttpHeaders headers, final HttpStatus status,
                                                                     final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final String error = ex.getRequestPartName() + " part is missing";
        errors.add(error);
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<>(apiStatusResponse, new HttpHeaders(), HttpStatus.BAD_REQUEST);
    }

    @Override
    protected ResponseEntity<Object> handleMissingServletRequestParameter(final MissingServletRequestParameterException ex,
                                                                          final HttpHeaders headers, final HttpStatus status,
                                                                          final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final String error = ex.getParameterName() + " parameter is missing";
        errors.add(error);
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<>(apiStatusResponse, new HttpHeaders(), HttpStatus.BAD_REQUEST);
    }

    @ExceptionHandler({MethodArgumentTypeMismatchException.class})
    public ResponseEntity<Object> handleMethodArgumentTypeMismatch(final MethodArgumentTypeMismatchException ex,
                                                                   final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final String error = ex.getName() + " should be of type " + ex.getRequiredType().getName();
        errors.add(error);
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<>(apiStatusResponse, new HttpHeaders(), HttpStatus.BAD_REQUEST);
    }

    @ExceptionHandler({ConstraintViolationException.class})
    public ResponseEntity<Object> handleConstraintViolation(final ConstraintViolationException ex, final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        for (final ConstraintViolation<?> violation : ex.getConstraintViolations()) {
            errors.add(violation.getRootBeanClass().getName() + " " + violation.getPropertyPath() + ": " + violation.getMessage());
        }
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<Object>(apiStatusResponse, new HttpHeaders(), HttpStatus.BAD_REQUEST);
    }

    // 404

    @Override
    protected ResponseEntity<Object> handleHttpMessageNotReadable(HttpMessageNotReadableException ex, HttpHeaders headers, HttpStatus status, WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        //final String error = "No handler found for " + ex.getHttpMethod() + " " + ex.getRequestURL();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<Object>(apiStatusResponse, new HttpHeaders(), HttpStatus.NOT_FOUND);
    }

    @Override
    protected ResponseEntity<Object> handleNoHandlerFoundException(final NoHandlerFoundException ex,
                                                                   final HttpHeaders headers, final HttpStatus status,
                                                                   final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final String error = "No handler found for " + ex.getHttpMethod() + " " + ex.getRequestURL();
        errors.add(error);
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<Object>(apiStatusResponse, new HttpHeaders(), HttpStatus.NOT_FOUND);
    }

    // 405

    @Override
    protected ResponseEntity<Object> handleHttpRequestMethodNotSupported(final HttpRequestMethodNotSupportedException ex,
                                                                         final HttpHeaders headers, final HttpStatus status,
                                                                         final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final StringBuilder builder = new StringBuilder();
        builder.append(ex.getMethod());
        builder.append(" method is not supported for this request. Supported methods are ");
        ex.getSupportedHttpMethods().forEach(t -> builder.append(t + " "));
        errors.add(builder.toString());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<>(apiStatusResponse, new HttpHeaders(), HttpStatus.METHOD_NOT_ALLOWED);
    }

    // 415

    @Override
    protected ResponseEntity<Object> handleHttpMediaTypeNotSupported(final HttpMediaTypeNotSupportedException ex,
                                                                     final HttpHeaders headers, final HttpStatus status,
                                                                     final WebRequest request) {
        ArrayList<String> errors = new ArrayList<>();
        final StringBuilder builder = new StringBuilder();
        builder.append(ex.getContentType());
        builder.append(" media type is not supported. Supported media types are ");
        ex.getSupportedMediaTypes().forEach(t -> builder.append(t + " "));
        errors.add(builder.toString());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<Object>(apiStatusResponse, new HttpHeaders(), HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    }

    // 500

    @ExceptionHandler({Exception.class})
    public ResponseEntity<Object> handleAll(final Exception ex, final WebRequest request) {
        log.debug("GlobalRestExceptionHandler::handleAll");
        log.error("error:" + ex.toString());
        ArrayList<String> errors = new ArrayList<>();
        errors.add(ex.getLocalizedMessage());
        final ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(false)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .withErrors(errors)
                .build();
        return new ResponseEntity<Object>(apiStatusResponse, new HttpHeaders(), HttpStatus.INTERNAL_SERVER_ERROR);
    }

}
