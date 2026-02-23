/*
        Insecure Web App (IWA)

        Copyright (C) 2021-2026 Micro Focus or one of its affiliates

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

package com.microfocus.example.api.controllers;

import com.microfocus.example.entity.Review;
import com.microfocus.example.exception.ReviewNotFoundException;
import com.microfocus.example.payload.request.ReviewRequest;
import com.microfocus.example.payload.response.ApiStatusResponse;
import com.microfocus.example.payload.response.ProductResponse;
import com.microfocus.example.payload.response.ReviewResponse;
import com.microfocus.example.service.ProductService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * A RESTFul controller for accessing product review information.
 *
 * @author Kevin A. Lee
 */
@RestController
@RequestMapping(value = "/api/v3/reviews")
@Tag(name = "reviews", description = "Review operations")
public class ApiReviewController {

    private static final org.slf4j.Logger log = LoggerFactory.getLogger(ApiReviewController.class);

    @Autowired
    private ProductService productService;

    @Operation(summary = "Find review by Id", description = "Find a review by UUID", tags = {"reviews"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ReviewResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Review Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @GetMapping(value = {"/{id}"}, produces =  {"application/json"})
    public ResponseEntity<ReviewResponse> findReviewById(
            @Parameter(description = "UUID of the review to be found. Cannot be empty.", example = "822f734a-3d13-4ebc-bff6-9c36d29866a6", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Retrieving review with UUID: " + id);
        if (!productService.reviewExistsById(id))
            throw new ReviewNotFoundException("Review with UUID: " + id.toString() + " does not exist.");
        Optional<Review> review = productService.findReviewById(id);
        return review.map(value -> new ResponseEntity<>(new ReviewResponse(value), HttpStatus.OK)).orElse(null);
    }

    @Operation(summary = "Find reviews by product and keyword(s)", description = "Product and keyword search by %keyword% format", tags = {"reviews"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(array = @ArraySchema(schema = @Schema(implementation = ProductResponse.class)))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @GetMapping(value = {""}, produces = {"application/json"})
    public ResponseEntity<List<ReviewResponse>> getReviewsByKeywords(
            @Parameter(description = "UUID of the product to find reviews for.", example = "eec467c8-5de9-4c7c-8541-7b31614d31a0") @RequestParam("pid") Optional<UUID> pid,
            @Parameter(description = "Keyword(s) search for reviews to be found.") @RequestParam("keywords") Optional<String> keywords,
            @Parameter(description = "Offset of the starting record. 0 indicates the first record.") @RequestParam("offset") Optional<Integer> offset,
            @Parameter(description = "Maximum records to return. The maximum value allowed is 50.") @RequestParam("limit") Optional<Integer> limit) {
        log.debug("API::Retrieving reviews by keyword(s)" + (pid.map(value -> " for product id:" + value).orElse("")));
        if (limit.isPresent()) {
            productService.setPageSize(limit.get());
        } else {
            productService.setPageSize(50);
        }
        String k = (keywords.orElse(""));
        Integer o = (offset.orElse(0));
        return pid.map(uuid -> new ResponseEntity<>(
            productService.getProductReviews(uuid, o, k).stream()
                .map(ReviewResponse::new)
                .collect(Collectors.toList()), HttpStatus.OK)).orElseGet(() -> new ResponseEntity<>(
            productService.getReviews(o, k).stream()
                .map(ReviewResponse::new)
                .collect(Collectors.toList()), HttpStatus.OK));
    }

    @Operation(summary = "Create a new review", description = "Creates a new review", tags = {"reviews"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ReviewResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "409", description = "Review Already Exists", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @PostMapping(value = {""}, produces = {"application/json"}, consumes = {"application/json"})
    @ResponseStatus(HttpStatus.CREATED)
    public ResponseEntity<ReviewResponse> createReview(
            @io.swagger.v3.oas.annotations.parameters.RequestBody(description = "") @Valid @RequestBody ReviewRequest newReview) {
        log.debug("API::Creating new review: " + newReview.toString());
        return new ResponseEntity<>(new ReviewResponse(productService.saveReviewFromApi(null, newReview)), HttpStatus.OK);
    }

    @Operation(summary = "Update an review", description = "Update an existing review", tags = {"reviews"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ReviewResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Review Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @PutMapping(value = {"/{id}"}, produces = {"application/json"}, consumes = {"application/json"})
    public ResponseEntity<ReviewResponse> updateReview(
            @io.swagger.v3.oas.annotations.parameters.RequestBody(description = "") @Valid @RequestBody ReviewRequest newReview,
            @Parameter(description = "UUID of the review to be updated. Cannot be empty.", example = "822f734a-3d13-4ebc-bff6-9c36d29866a6", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Updating review with UUID: " + id);
        return new ResponseEntity<>(new ReviewResponse(productService.saveReviewFromApi(id, newReview)), HttpStatus.OK);
    }

    @Operation(summary = "Delete a review", description = "Delete an review", tags = {"reviews"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Review Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class)))
    })
    @DeleteMapping (value = {"/{id}"})
    public ResponseEntity<ApiStatusResponse> deleteReview(
            @Parameter(description = "UUID of the review to be updated. Cannot be empty.", example = "822f734a-3d13-4ebc-bff6-9c36d29866a6", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Deleting review with UUID: " + id);
        productService.deleteReviewById(id);
        ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(true)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .build();
        return new ResponseEntity<>(apiStatusResponse, HttpStatus.OK);
    }

}


