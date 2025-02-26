/*
        Insecure Web App (IWA)

        Copyright (C) 2021 Micro Focus or one of its affiliates

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

import com.microfocus.example.payload.request.ProductRequest;
import com.microfocus.example.payload.response.ApiStatusResponse;
import com.microfocus.example.entity.Product;
import com.microfocus.example.exception.ProductNotFoundException;
import com.microfocus.example.payload.response.ProductResponse;
import com.microfocus.example.service.ProductService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.io.InputStream;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * A RESTFul controller for accessing product information.
 *
 * @author Kevin A. Lee
 */
@RestController
@RequestMapping(value = "/api/v3/products")
@Tag(name = "products", description = "Product operations")
public class ApiProductController {

    private static final org.slf4j.Logger log = LoggerFactory.getLogger(ApiProductController.class);

    @Autowired
    private ProductService productService;

    @Operation(summary = "Find products by keyword(s)", description = "Keyword search by %keyword% format", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(array = @ArraySchema(schema = @Schema(implementation = ProductResponse.class)))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @GetMapping(value = {""}, produces = {"application/json"})
    public ResponseEntity<List<ProductResponse>> getProductsByKeywords(
            @Parameter(description = "Keyword(s) search for products to be found.") @RequestParam("keywords") Optional<String> keywords,
            @Parameter(description = "Offset of the starting record. 0 indicates the first record.") @RequestParam("offset") Optional<Integer> offset,
            @Parameter(description = "Maximum records to return. The maximum value allowed is 50.") @RequestParam("limit") Optional<Integer> limit) {
        log.debug("API::Retrieving products by keyword(s)");
        if (limit.isPresent()) {
            productService.setPageSize(limit.orElse(productService.getPageSize()));
        }
        String k = (keywords.orElse(""));
        Integer o = (offset.orElse(0));
        return new ResponseEntity<>(
            productService.getAllProducts(o, k).stream()
                .map(ProductResponse::new)
                .collect(Collectors.toList()), HttpStatus.OK);
    }

    @Operation(summary = "Find product by Id", description = "Find a product by UUID", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ProductResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Product Not Found", content = @Content(schema = @Schema(implementation = ProductNotFoundException.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @GetMapping(value = {"/{id}"}, produces =  {"application/json"})
    public ResponseEntity<ProductResponse> findProductById(
            @Parameter(description = "UUID of the product to be found. Cannot be empty.", example = "eec467c8-5de9-4c7c-8541-7b31614d31a0", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Retrieving product with UUID: " + id);
        if (!productService.productExistsById(id))
            throw new ProductNotFoundException("Product with UUID: " + id.toString() + " does not exist.");
        Optional<Product> product = productService.findProductById(id);
        return product.map(value -> new ResponseEntity<>(new ProductResponse(value), HttpStatus.OK)).orElse(null);
    }

    @Operation(summary = "Create a new product", description = "Creates a new product", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ProductResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "409", description = "Product Already Exists", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @PostMapping(value = {""}, produces = {"application/json"}, consumes = {"application/json"})
    @ResponseStatus(HttpStatus.CREATED)
    public ResponseEntity<ProductResponse> createProduct(
            @io.swagger.v3.oas.annotations.parameters.RequestBody(description = "") @Valid @RequestBody ProductRequest newProduct) {
        log.debug("API::Creating new product: " + newProduct.toString());
        return new ResponseEntity<>(new ProductResponse(productService.saveProductFromApi(null, newProduct)), HttpStatus.OK);
    }

    @Operation(summary = "Update a product", description = "Update an existing product", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ProductResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Product Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @PutMapping(value = {"/{id}"}, produces = {"application/json"}, consumes = {"application/json"})
    public ResponseEntity<ProductResponse> updateProduct(
            @io.swagger.v3.oas.annotations.parameters.RequestBody(description = "") @Valid @RequestBody ProductRequest newProduct,
            @Parameter(description = "UUID of the product to be updated. Cannot be empty.", example = "eec467c8-5de9-4c7c-8541-7b31614d31a0", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Updating product with UUID: " + id);
        return new ResponseEntity<>(new ProductResponse(productService.saveProductFromApi(id, newProduct)), HttpStatus.OK);
    }

    @Operation(summary = "Delete a product", description = "Delete a product", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Product Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class)))
    })
    @DeleteMapping (value = {"/{id}"})
    public ResponseEntity<ApiStatusResponse> deleteProduct(
            @Parameter(description = "UUID of the product to be updated. Cannot be empty.", example = "eec467c8-5de9-4c7c-8541-7b31614d31a0", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Deleting product with UUID: " + id);
        productService.deleteProductById(id);
        ApiStatusResponse apiStatusResponse = new ApiStatusResponse
                .ApiResponseBuilder()
                .withSuccess(true)
                .atTime(LocalDateTime.now(ZoneOffset.UTC))
                .build();
        return new ResponseEntity<>(apiStatusResponse, HttpStatus.OK);
    }

    @Operation(summary = "Get product image by Id", description = "Get a product's image by its UUID", tags = {"products"}, security = @SecurityRequirement(name = "JWT Authentication"))
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Success", content = @Content(schema = @Schema(implementation = ProductResponse.class))),
            @ApiResponse(responseCode = "400", description = "Bad Request", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthorized", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "403", description = "Forbidden", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "404", description = "Product Not Found", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
            @ApiResponse(responseCode = "500", description = "Internal Server Error", content = @Content(schema = @Schema(implementation = ApiStatusResponse.class))),
    })
    @GetMapping(value = {"/{id}/image"}, produces =  {"application/json"})
    public ResponseEntity<InputStreamResource> findProductImageById(
            @Parameter(description = "UUID of the product. Cannot be empty.", example = "eec467c8-5de9-4c7c-8541-7b31614d31a0", required = true) @PathVariable("id") UUID id) {
        log.debug("API::Retrieving product image for UUID: " + id);
        if (!productService.productExistsById(id))
            throw new ProductNotFoundException("Product with UUID: " + id.toString() + " does not exist.");
        Optional<Product> product = productService.findProductById(id);
        MediaType contentType = MediaType.IMAGE_JPEG;
        InputStream in = getClass().getResourceAsStream("/static/img/products/"+product.get().getImage());
        if (in == null) {
            log.error("Could not find resource /static/img/products/{}", product.get().getImage());
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok()
                .contentType(contentType)
                .body(new InputStreamResource(in));
    }


}


