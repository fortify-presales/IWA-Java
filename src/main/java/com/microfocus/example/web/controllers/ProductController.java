/*
        Insecure Web App (IWA)

        Copyright (C) 2020-2024 Micro Focus or one of its affiliates

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

package com.microfocus.example.web.controllers;

import com.microfocus.example.config.LocaleConfiguration;
import com.microfocus.example.entity.Product;
import com.microfocus.example.service.ProductService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.core.io.UrlResource;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.util.ResourceUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.servlet.http.HttpServletRequest;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.MalformedURLException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.Principal;
import java.util.*;

/**
 * Controller for product pages
 *
 * @author kadraman
 */
@RequestMapping("/products")
@Controller
public class ProductController extends AbstractBaseController {

    private final Logger log = LoggerFactory.getLogger(getClass());
    private final String CONTROLLER_NAME = getClass().getName();

    @Value("${app.data.page-size:25}")
    private Integer defaultPageSize;

    @Autowired
    ProductService productService;

    @Autowired
    LocaleConfiguration localeConfiguration;

    @Autowired
    private ResourceLoader resourceLoader;

    @Override
    LocaleConfiguration GetLocaleConfiguration() {
        return localeConfiguration;
    }

    @Override
    String GetControllerName() {
        return CONTROLLER_NAME;
    }

    @Value("${spring.profiles.active:default}")
    private String activeProfile;

    @GetMapping("/xss")
    @ResponseBody
    public ResponseEntity<String> getKeywordsContent(@Param("keywords") String keywords) {

    	String retContent = "Product search using: " + keywords;

        return ResponseEntity.ok().body(retContent);
    }

    @GetMapping(value = {"", "/"})
    public String index(Model model, @Param("keywords") String keywords, @Param("limit") Integer limit, Principal principal) {
        log.debug("Searching for products using keywords: " + ((keywords == null || keywords.isEmpty()) ? "none" : keywords));
        productService.setPageSize((limit == null ? defaultPageSize : limit));
        List<Product> products = productService.getAllActiveProducts(0, keywords);
        model.addAttribute("keywords", keywords);
        model.addAttribute("products", products);
        model.addAttribute("productCount", products.size());
        model.addAttribute("productTotal", productService.count());
        this.setModelDefaults(model, principal, "index");
        return "products/index";
    }

    @GetMapping("/{id}")
    public String viewProduct(@PathVariable("id") UUID productId, Model model, Principal principal) {
        Optional<Product> optionalProduct = productService.findProductById(productId);
        if (optionalProduct.isPresent()) {
            model.addAttribute("product", optionalProduct.get());
        } else {
            model.addAttribute("message", "Internal error accessing product!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "products/not-found";
        }
        this.setModelDefaults(model, principal, "view");
        return "products/view";
    }

    @GetMapping("/{id}/download/{fileName:.+}")
    public ResponseEntity<Resource> downloadFile(@PathVariable(value = "id") UUID productId,
                                                 @PathVariable String fileName, HttpServletRequest request) {

        Resource resource;
        File dataDir;

        if (activeProfile.contains("dev") || activeProfile.contains("test")) {
            log.debug("Running dev/test profile: downloading from filesystem");
            try {
                dataDir = ResourceUtils.getFile("classpath:data");
            } catch (FileNotFoundException e) {
                e.printStackTrace();
                return ResponseEntity.notFound().build();
            }

            log.debug("Using data directory: " + dataDir.getAbsolutePath());
            String fileBasePath = dataDir.getAbsolutePath() + File.separatorChar + productId.toString() + File.separatorChar;
            Path path = Paths.get(fileBasePath + fileName);
            try {
                resource = new UrlResource(path.toUri());
            } catch (MalformedURLException e) {
                e.printStackTrace();
                return ResponseEntity.notFound().build();
            }
        } else {
            log.info("Running production profile: downloading from JAR");
            resource = resourceLoader
                    .getResource("classpath:data" + File.separatorChar + productId.toString() + File.separatorChar + fileName);
            if (!resource.exists()) {
                log.error("Could not find resource classpath:data/{}", fileName);
                return ResponseEntity.notFound().build();
            }
        }

        // Try to determine file's content type
        String contentType = null;
        try {
            contentType = request.getServletContext().getMimeType(resource.getFile().getAbsolutePath());
        } catch (IOException ex) {
            log.error("Could not determine Content Type.");
        }
        log.info("Resource filename: {}", resource.getFilename());
        log.info("Content Type: {}", contentType.toString());

        // Fallback to the default content type if type could not be determined
        if (contentType == null) {
            contentType = "application/octet-stream";
        }

        return ResponseEntity.ok().contentType(MediaType.parseMediaType(contentType))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + resource.getFilename() + "\"")
                .body(resource);
    }

}
