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

import com.google.zxing.WriterException;
import com.microfocus.example.config.LocaleConfiguration;
import com.microfocus.example.entity.*;
import com.microfocus.example.exception.*;
import com.microfocus.example.service.EmailSenderService;
import com.microfocus.example.service.ProductService;
import com.microfocus.example.service.StorageService;
import com.microfocus.example.service.UserService;
import com.microfocus.example.service.UserValidationService;
import com.microfocus.example.utils.WebUtils;
import com.microfocus.example.web.form.*;
import org.json.JSONArray;
import org.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.session.SessionRegistry;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.validation.ObjectError;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.MvcUriComponentsBuilder;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;
import org.w3c.dom.Document;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;

import javax.validation.Valid;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.Principal;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Controller for user pages
 *
 * @author kadraman
 */
@RequestMapping("/user")
@Controller
@SessionAttributes("user")
public class UserController extends AbstractBaseController {

    private final Logger log = LoggerFactory.getLogger(getClass());
    private final String CONTROLLER_NAME = getClass().getName();

    @Value("${AUTHENTICATION_ERROR;Invalid authentication credentials were supplied.")
    private String AUTHENTICATION_ERROR;

    @Value("${USER_NOT_FOUND_ERROR:A user to be changed was not found.}")
    private String USER_NOT_FOUND_ERROR;

    @Value("${USERNAME_TAKEN_ERROR:A username was used that is already taken.")
    private String USERNAME_TAKEN_ERROR;

    @Value(("${EMAIL_ADDRESS_TAKEN_ERROR:An email address was used that is already taken.}"))
    private String EMAIL_ADDRESS_TAKEN_ERROR;

    @Autowired
    private UserService userService;

    @Autowired
    private UserValidationService validationService;

    @Autowired
    private ProductService productService;

    @Autowired
    private StorageService storageService;

    @Value("${app.mail.from-name}")
    private String emailFromName;

    @Value("${app.mail.from-address}")
    private String emailFromAddress;

    @Value("${app.url}")
    private String appUrl;

    @Value("${app.messages.home}")
    private final String message = "Hello World";

    @Autowired
    EmailSenderService emailSenderService;

    @Autowired
    private SessionRegistry sessionRegistry;

    @Autowired
    LocaleConfiguration localeConfiguration;

    private String thRCECMD = "";

    @Override
    LocaleConfiguration GetLocaleConfiguration() {
        return localeConfiguration;
    }

    @Override
    String GetControllerName() {
        return CONTROLLER_NAME;
    }

    @GetMapping(value = {"", "/"})
    public String userHome(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            UserForm userForm = new UserForm(optionalUser.get());
            model.addAttribute("username", userForm.getUsername());
            model.addAttribute("fullname", userForm.getFirstName() + " " + userForm.getLastName());
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
            model.addAttribute("unreadMessageCount", userService.getUserUnreadMessageCount(user.getId()));
            model.addAttribute("unshippedOrderCount", userService.getUserUnshippedOrderCount(user.getId()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "home");
        return "user/home";
    }

    @GetMapping("/xss")
    @ResponseBody
    public ResponseEntity<String> getUserContent(@Param("keywords") String keywords) {

    	String retContent = "User search using: " + keywords;

        return ResponseEntity.ok().body(retContent);
    }

    @GetMapping(value = {"/profile"})
    public String userProfile(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            UserForm userForm = new UserForm(optionalUser.get());
            String qrUrl = getQRBarcodeURL(user.getUsername(), user.getSecret());
            model.addAttribute("userForm", userForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
            model.addAttribute("qrUrl", qrUrl);
            model.addAttribute("qrSecret", user.getSecret());
            model.addAttribute("unreadMessageCount", userService.getUserUnreadMessageCount(user.getId()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "profile");
        return "user/profile";
    }

    @GetMapping("/editProfile")
    public String userEditProfile(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            UserForm userForm = new UserForm(optionalUser.get());
            model.addAttribute("userForm", userForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "edit-profile");
        return "user/edit-profile";
    }

    @GetMapping(value = {"/security"})
    public String userSecurity(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            UserForm securityForm = new UserForm(optionalUser.get());
            String qrUrl = getQRBarcodeURL(user.getUsername(), user.getSecret());
            byte[] image = new byte[0];
            try {
                // Generate and Return Qr Code in Byte Array
                image = WebUtils.getQRCodeImage(qrUrl,250,250);
            } catch (WriterException | IOException e) {
                e.printStackTrace();
            }
            // Convert Byte Array into Base64 Encode String
            String qrCode = Base64.getEncoder().encodeToString(image);

            model.addAttribute("securityForm", securityForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
            model.addAttribute("qrCode", qrCode);
            model.addAttribute("qrSecret", user.getSecret());
            model.addAttribute("unreadMessageCount", userService.getUserUnreadMessageCount(user.getId()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "security");
        return "user/security";
    }

    @GetMapping("/editSecurity")
    public String userEditSecurity(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            SecurityForm securityForm = new SecurityForm(optionalUser.get());
            model.addAttribute("securityForm", securityForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "edit-security");
        return "user/edit-security";
    }

    @PostMapping("/saveSecurity")
    public String userSaveSecurity(@Valid @ModelAttribute("securityForm") SecurityForm securityForm,
                                  BindingResult bindingResult, Model model,
                                  RedirectAttributes redirectAttributes,
                                  Principal principal) {
        String err = validationService.validateUser(securityForm);
        if (!err.isEmpty()) {
            ObjectError error = new ObjectError("global", err);
            bindingResult.addError(error);
        }                            
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "edit-security");
            return "user/edit-security";
        } else {
            try {
                userService.saveUserFromSecurityForm(securityForm);
                redirectAttributes.addFlashAttribute("message", "Security updated successfully.");
                redirectAttributes.addFlashAttribute("alertClass", "alert-success");
                this.setModelDefaults(model, principal, "security");
                return "redirect:/user/security";
            } catch (InvalidPasswordException ex) {
                log.error(AUTHENTICATION_ERROR);
                FieldError passwordError = new FieldError("securityForm", "password", ex.getMessage());
                bindingResult.addError(passwordError);
            } catch (UserNotFoundException ex) {
                log.error(USER_NOT_FOUND_ERROR);
                FieldError usernameError = new FieldError("securityForm", "username", ex.getMessage());
                bindingResult.addError(usernameError);
            }
        }
        this.setModelDefaults(model, principal, "security");
        return "user/security";
    }

    @GetMapping("/changePassword")
    public String userChangePassword(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        if (optionalUser.isPresent()) {
            PasswordForm passwordForm = new PasswordForm(optionalUser.get());
            model.addAttribute("passwordForm", passwordForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "change-password");
        return "user/change-password";
    }

    //
    // Messages
    //

    @GetMapping("/messages")
    public String userMessages(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        List<Message> messages = userService.getUserMessages(user.getId());
        model.addAttribute("messages", messages);
        model.addAttribute("unreadMessageCount", userService.getUserUnreadMessageCount(user.getId()));
        model.addAttribute("totalMessageCount", messages.size());
        this.setModelDefaults(model, principal, "index");
        return "user/messages/index";
    }

    /*
    @GetMapping("/unread-message-count")
    @ResponseBody
    public String getUserMessageCount(Model model, Principal principal) {
        UUID loggedInUserId;
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            loggedInUserId = loggedInUser.getId();
            long userMessageCount = userService.getUserUnreadMessageCount(loggedInUserId);
            return Long.toString(userMessageCount);
        } else {
            return "0";
        }
    }*/

    @GetMapping("/messages/{id}")
    public String viewMessage(@PathVariable("id") UUID messageId,
                           Model model, Principal principal) {
        UUID loggedInUserId;
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            loggedInUserId = loggedInUser.getId();
        } else {
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        Optional<Message> optionalMessage = userService.findMessageById(messageId);
        if (optionalMessage.isPresent()) {
            // does user have permission to read this message?
            UUID messageUserId = optionalMessage.get().getUser().getId();
            if (!messageUserId.equals(loggedInUserId)) {
                this.setModelDefaults(model, principal, "access-denied");
                return "user/messages/access-denied";
            }
            MessageForm messageForm = new MessageForm(optionalMessage.get());
            model.addAttribute("messageForm", messageForm);
            // mark messages as read
            userService.markMessageAsReadById(messageId);
        } else {
            model.addAttribute("message", "Internal error accessing message!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/messages/not-found";
        }
        this.setModelDefaults(model, principal, "view");
        return "user/messages/view";
    }

    //
    // Orders
    //

    @GetMapping("/orders")
    public String userOrders(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        List<Order> orders = userService.getUserOrders(user.getId());
        model.addAttribute("orders", orders);
        model.addAttribute("unshippedOrderCount", userService.getUserUnshippedOrderCount(user.getId()));
        model.addAttribute("totalOrderCount", orders.size());
        this.setModelDefaults(model, principal, "index");
        return "user/orders/index";
    }

    @GetMapping("/unshipped-order-count")
    @ResponseBody
    public String getUnshippedOrderCount(Model model, Principal principal) {
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            long unshippedOrderCount = userService.getUserUnshippedOrderCount(loggedInUser.getId());
            return Long.toString(unshippedOrderCount);
        } else {
            return "0";
        }
    }

    @GetMapping("/orders/{id}")
    public String viewOrder(@PathVariable("id") UUID orderId,
                              Model model, Principal principal) {
        UUID loggedInUserId;
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            loggedInUserId = loggedInUser.getId();
        } else {
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        Optional<Order> optionalOrder = userService.findOrderById(orderId);
        if (optionalOrder.isPresent()) {
            // does user have permission to view this order?
            UUID orderUserId = optionalOrder.get().getUser().getId();
            if (!orderUserId.equals(loggedInUserId)) {
                this.setModelDefaults(model, principal, "access-denied");
                return "user/orders/access-denied";
            }
            OrderForm orderForm = new OrderForm(optionalOrder.get());
            model.addAttribute("orderForm", orderForm);
        } else {
            model.addAttribute("message", "Internal error accessing order!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/orders/not-found";
        }
        this.setModelDefaults(model, principal, "view");
        return "user/orders/view";
    }

    //
    // Product Reviews
    //

    @GetMapping("/reviews")
    public String userReviews(Model model, Principal principal) {
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        List<Review> reviews = productService.findReviewByUserId(user.getId());
        model.addAttribute("reviews", reviews);
        model.addAttribute("reviewCount", reviews.size());
        this.setModelDefaults(model, principal, "index");
        return "user/reviews/index";
    }

    @GetMapping("/reviews/{id}")
    public String viewReview(@PathVariable("id") UUID reviewId,
                            Model model, Principal principal) {
        UUID loggedInUserId;
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            loggedInUserId = loggedInUser.getId();
        } else {
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        Optional<Review> optionalReview = productService.findReviewById(reviewId);
        if (optionalReview.isPresent()) {
            // does user have permission to view this order?
            UUID reviewUserId = optionalReview.get().getUser().getId();
            if (!reviewUserId.equals(loggedInUserId)) {
                log.error("User id: " + loggedInUserId + " trying to access review for: " + reviewUserId);
                this.setModelDefaults(model, principal, "access-denied");
                return "user/reviews/access-denied";
            }
            ReviewForm reviewForm = new ReviewForm(optionalReview.get());
            model.addAttribute("reviewForm", reviewForm);
        } else {
            model.addAttribute("message", "Internal error accessing review!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/reviews/not-found";
        }
        this.setModelDefaults(model, principal, "view");
        return "user/reviews/view";
    }

    @GetMapping("/reviews/{id}/edit")
    public String editReview(@PathVariable("id") UUID reviewId,
                             Model model, Principal principal) {
        UUID loggedInUserId;
        if (principal != null) {
            CustomUserDetails loggedInUser = (CustomUserDetails) ((Authentication) principal).getPrincipal();
            loggedInUserId = loggedInUser.getId();
        } else {
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        Optional<Review> optionalReview = productService.findReviewById(reviewId);
        if (optionalReview.isPresent()) {
            // does user have permission to view this order?
            UUID reviewUserId = optionalReview.get().getUser().getId();
            if (!reviewUserId.equals(loggedInUserId)) {
                log.error("User id: " + loggedInUserId + " trying to access review for: " + reviewUserId);
                this.setModelDefaults(model, principal, "access-denied");
                return "user/reviews/access-denied";
            }
            ReviewForm reviewForm = new ReviewForm(optionalReview.get());
            model.addAttribute("reviewForm", reviewForm);
        } else {
            model.addAttribute("message", "Internal error accessing review!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/reviews/not-found";
        }
        this.setModelDefaults(model, principal, "edit");
        return "user/reviews/edit";
    }


    @GetMapping("/reviews/new")
    public String newReview(@RequestParam("pid") Optional<UUID> pid,
                            Model model, Principal principal) {
        UUID productId = (pid.isPresent() ? pid.get() : null);
        if (!pid.isPresent() || !productService.productExistsById(productId)) {
            model.addAttribute("message", "The product id '" + productId.toString() + "' is invalid!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "product-not-found");
            return "user/reviews/product-not-found";
        }
        CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
        Optional<User> optionalUser = userService.findUserById(user.getId());
        Optional<Product> optionalProduct = productService.findProductById(productId);
        if (optionalUser.isPresent()) {
            NewReviewForm newReviewForm = new NewReviewForm(optionalUser.get().getId(), productId, optionalProduct.get().getName());
            model.addAttribute("newReviewForm", newReviewForm);
            model.addAttribute("userInfo", WebUtils.toString(user.getUserDetails()));
        } else {
            model.addAttribute("message", "Internal error accessing user!");
            model.addAttribute("alertClass", "alert-danger");
            this.setModelDefaults(model, principal, "not-found");
            return "user/not-found";
        }
        this.setModelDefaults(model, principal, "new");
        return "user/reviews/new";
    }

    @PostMapping("/reviews/new")
    public String newReview(@Valid @ModelAttribute("newReviewForm") NewReviewForm newReviewForm,
                                  BindingResult bindingResult, Model model,
                                  RedirectAttributes redirectAttributes,
                                  Principal principal) {
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "new");
            return "user/reviews/new";
        } else {
            productService.newReviewFromNewReviewForm(newReviewForm);
            redirectAttributes.addFlashAttribute("message", "Review created successfully.");
            redirectAttributes.addFlashAttribute("alertClass", "alert-success");
            this.setModelDefaults(model, principal, "index");
            return "redirect:/user/reviews";
        }
    }

    @PostMapping("/reviews/save")
    public String saveReview(@Valid @ModelAttribute("reviewForm") ReviewForm reviewForm,
                            BindingResult bindingResult, Model model,
                            RedirectAttributes redirectAttributes,
                            Principal principal) {
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "edit");
            return "user/reviews/edit";
        } else {
            productService.saveReviewFromUserReviewForm(reviewForm);
            redirectAttributes.addFlashAttribute("message", "Review updated successfully.");
            redirectAttributes.addFlashAttribute("alertClass", "alert-success");
            this.setModelDefaults(model, principal, "index");
            return "redirect:/user/reviews";
        }
    }

    //
    //
    //

    @PostMapping("/saveProfile")
    public String userSaveProfile(@Valid @ModelAttribute("userForm") UserForm userForm,
                                  BindingResult bindingResult, Model model,
                                  RedirectAttributes redirectAttributes,
                                  Principal principal) {
        String err = validationService.validateUser(userForm);
        if (!err.isEmpty()) {
            ObjectError error = new ObjectError("global", err);
            bindingResult.addError(error);
        }
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "edit-profile");
            return "user/edit-profile";
        } else {
            try {
                userService.saveUserFromUserForm(userForm);
                redirectAttributes.addFlashAttribute("message", "Profile updated successfully.");
                redirectAttributes.addFlashAttribute("alertClass", "alert-success");
                this.setModelDefaults(model, principal, "profile");
                return "redirect:/user/profile";
            } catch (InvalidPasswordException ex) {
                log.error(AUTHENTICATION_ERROR);
                FieldError passwordError = new FieldError("userForm", "password", ex.getMessage());
                bindingResult.addError(passwordError);
            } catch (UserNotFoundException ex) {
                log.error(USER_NOT_FOUND_ERROR);
                FieldError usernameError = new FieldError("userForm", "username", ex.getMessage());
                bindingResult.addError(usernameError);
            }
        }
        this.setModelDefaults(model, principal, "profile");
        return "user/profile";
    }

    @PostMapping("/savePassword")
    public String userSavePassword(@Valid @ModelAttribute("passwordForm") PasswordForm passwordForm,
                                   BindingResult bindingResult, Model model,
                                   RedirectAttributes redirectAttributes,
                                   Principal principal) {
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "change-password");
            return "user/change-password";
        } else {
            try {
                CustomUserDetails user = (CustomUserDetails) ((Authentication) principal).getPrincipal();
                Optional<User> optionalUser = userService.findUserById(user.getId());
                if (optionalUser.isPresent()) {
                    userService.updateUserPasswordFromPasswordForm(user.getId(), passwordForm);
                }
                redirectAttributes.addFlashAttribute("message", "Password updated successfully.");
                redirectAttributes.addFlashAttribute("alertClass", "alert-success");
                return "redirect:/logout";
            } catch (InvalidPasswordException ex) {
                log.error(AUTHENTICATION_ERROR);
                FieldError passwordError = new FieldError("passwordForm", "password", ex.getMessage());
                bindingResult.addError(passwordError);
            } catch (UserNotFoundException ex) {
                log.error(USER_NOT_FOUND_ERROR);
                FieldError usernameError = new FieldError("passwordForm", "username", ex.getMessage());
                bindingResult.addError(usernameError);
            }
        }
        this.setModelDefaults(model, principal, "home");
        return "user/home";
    }

    @PostMapping("/messages/delete/{id}")
    public String userDeleteMessage(@PathVariable("id") UUID messageId,
                              Model model, Principal principal) {
        userService.deleteMessageById(messageId);
        model.addAttribute("message", "Successfully deleted message!");
        model.addAttribute("alertClass", "alert-success");
        return "redirect:/user/messages/";
    }

    @PostMapping("/reviews/delete/{id}")
    public String userDeleteReview(@PathVariable("id") UUID reviewId,
                                    Model model, Principal principal) {
        productService.deleteReviewById(reviewId);
        model.addAttribute("message", "Successfully deleted review!");
        model.addAttribute("alertClass", "alert-success");
        return "redirect:/user/reviews/";
    }

    @GetMapping("/register")
    public String registerUser(Model model, Principal principal) {
        RegisterUserForm registerUserForm = new RegisterUserForm();
        model.addAttribute("registerUserForm", registerUserForm);
        this.setModelDefaults(model, principal, "register");
        return "user/register";
    }

    @PostMapping("/register")
    public String registerUser(@Valid @ModelAttribute("registerUserForm") RegisterUserForm registerUserForm,
                               BindingResult bindingResult, Model model,
                               RedirectAttributes redirectAttributes,
                               Principal principal) {
        String err = validationService.validateUser(registerUserForm);
        if (!err.isEmpty()) {
            ObjectError error = new ObjectError("global", err);
            bindingResult.addError(error);
        }
        if (bindingResult.hasErrors()) {
            this.setModelDefaults(model, principal, "register");
            return "user/register";
        } else {
            try {
                log.debug("Registering user {}", registerUserForm);
                User u = userService.registerUser(registerUserForm);
                String targetUrl = appUrl + "/user/verify?email=" + u.getEmail() + "&code=" + u.getVerifyCode();

                Mail mail = new Mail();
                mail.setMailTo(u.getEmail());
                mail.setFrom(emailFromAddress);
                mail.setReplyTo(emailFromAddress);
                mail.setSubject("[IWA Pharmacy Direct] Verify your account");

                Map<String, Object> props = new HashMap<String, Object>();
                props.put("to", u.getFirstName() + " " + u.getLastName());
                props.put("message", "Please verify your account by clicking on the following link: " + targetUrl);
                props.put("from", emailFromName);
                mail.setProps(props);

                try {
                   emailSenderService.sendEmail(mail, "email/default");
                } catch (Exception ex) {
                   log.error(ex.getLocalizedMessage());
                }

                this.setModelDefaults(model, null, "verify");
                return "redirect:/user/verify?email="+u.getEmail()+"&status=new";
            } catch (UsernameTakenException ex) {
                log.error(USERNAME_TAKEN_ERROR);
                FieldError usernameError = new FieldError("registerUserForm", "username", ex.getMessage());
                bindingResult.addError(usernameError);
            } catch (EmailAddressTakenException ex) {
               log.error(EMAIL_ADDRESS_TAKEN_ERROR);
               FieldError emailError = new FieldError("registerUserForm", "email", ex.getMessage());
               bindingResult.addError(emailError);
           }
        }
        this.setModelDefaults(model, principal, "register");
        return "user/register";
    }

    @GetMapping("/verify")
    public String verifyUser(@RequestParam("email") Optional<String> usersEmail,
                             @RequestParam("code") Optional<String> verificationCode,
                             @RequestParam("status") Optional<String> statusCode,
                             RedirectAttributes redirectAttributes,
                             Model model) {

        String email = Optional.of(usersEmail).get().orElse(null);
        String code = Optional.of(verificationCode).get().orElse(null);
        String status = Optional.of(statusCode).get().orElse(null);

        if (status != null && status.equals("new")) {
            model.addAttribute("message", "Your registration details have been stored. Please check your email to verify your details.");
            model.addAttribute("alertClass", "alert-success");
            VerifyUserForm verifyUserForm = new VerifyUserForm(usersEmail, verificationCode);
            model.addAttribute("verifyUserForm", verifyUserForm);
            this.setModelDefaults(model, null, "verify");
            return "user/verify";
        } else if ((email == null || email.isEmpty()) || (code == null || code.isEmpty())) {
            log.error("insufficient parameters");
            model.addAttribute("message", "You need to supply both an email address and verification code.");
            model.addAttribute("alertClass", "alert-danger");
            VerifyUserForm verifyUserForm = new VerifyUserForm(usersEmail, verificationCode);
            model.addAttribute("verifyUserForm", verifyUserForm);
            this.setModelDefaults(model, null, "verify");
            return "user/verify";
        } else {

            try {
                User u = userService.verifyUserRegistration(email, code);
                if (u != null) {
                    log.debug("Successfully verified user '" + email + "'");
                    redirectAttributes.addFlashAttribute("message", "Your account has been successfully verified. Please login.");
                    redirectAttributes.addFlashAttribute("alertClass", "alert-success");
                } else {
                    log.error("Unknown error verifying user!");
                    redirectAttributes.addFlashAttribute("message", "There was an error verifying your account, please contact support!");
                    redirectAttributes.addFlashAttribute("alertClass", "alert-danger");
                }
            } catch (UserNotFoundException ex) {
                log.error("Could not find user '" + email + "' to verify: " + ex.getLocalizedMessage());
                redirectAttributes.addFlashAttribute("message", "The account being verified does not exist. Please try registering again or contact support.");
                redirectAttributes.addFlashAttribute("alertClass", "alert-danger");
            }

            return "redirect:/login";
        }

    }

    //
    // File uploads
    //

    @GetMapping("/uploadFile")
    public String listUploadedFiles(@Valid @ModelAttribute("uploadForm") UploadForm uploadForm,
                                    BindingResult bindingResult, Model model,
                                    RedirectAttributes redirectAttributes,
                                    Principal principal) throws IOException {

        model.addAttribute("files", storageService.loadAll().map(
                path -> MvcUriComponentsBuilder.fromMethodName(UserController.class,
                        "serveFile", path.getFileName().toString()).build().toUri().toString())
                .collect(Collectors.toList()));

        return "user/upload-file";
    }

    @GetMapping("/files/{filename:.+}")
    @ResponseBody
    public ResponseEntity<Resource> serveFile(@PathVariable String filename) {

        Resource file = storageService.loadAsResource(filename);
        return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + file.getFilename() + "\"").body(file);
    }

    @PostMapping("/files/upload")
    public String handleFileUpload(@RequestParam("file") MultipartFile file,
                                   RedirectAttributes redirectAttributes) {

        storageService.store(file);
        redirectAttributes.addFlashAttribute("message",
                "You successfully uploaded " + file.getOriginalFilename() + "!");

        return "redirect:/user/upload-file";
    }

    @GetMapping("/upload-xml-file")
    public String listUploadedXMLFiles(@Valid @ModelAttribute("uploadForm") UploadForm uploadForm,
                                    BindingResult bindingResult, Model model,
                                    RedirectAttributes redirectAttributes,
                                    Principal principal) throws IOException {

    	JSONArray filesJsonAry = new JSONArray();

    	List<String> mimeTypeList = new ArrayList<>();
    	mimeTypeList.add("text/xml");
    	mimeTypeList.add("application/xml");

    	Stream<Path> filePaths = storageService.loadAll(mimeTypeList);
    	filesJsonAry.putAll(filePaths.map(path -> {
        	JSONObject fileJsonObj = new JSONObject();
        	String url = MvcUriComponentsBuilder.fromMethodName(UserController.class,
                    "serveXMLFile", path.getFileName().toString()).build().toUri().toString();
        	fileJsonObj.put("name", path.getFileName());
        	fileJsonObj.put("url", url);
        	fileJsonObj.put("content", getXMLFileContent(path.toString()));
        	return fileJsonObj;
    	}).collect(Collectors.toList()));

        model.addAttribute("files", filesJsonAry.toList());

        return "user/upload-xml-file";
    }

    private String getXMLFileContent(String filename) {
        Path fpath = storageService.load(filename);

        String xmlContent = "";
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        try {
			dbf.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, false);
	        DocumentBuilder db = dbf.newDocumentBuilder();
	        Document doc = db.parse(fpath.toFile());
	        try (ByteArrayOutputStream bytesOutStream = new ByteArrayOutputStream()) {
	        	writeXml(doc, bytesOutStream);
	        	xmlContent = bytesOutStream.toString();
	        } catch (IOException | TransformerException e) {
	        	e.printStackTrace();
	        }
		} catch (ParserConfigurationException | IOException | SAXException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}

        return xmlContent;

    }

    @GetMapping("/files/xml/{filename:.+}")
    @ResponseBody
    public ResponseEntity<Resource> serveXMLFile(@PathVariable String filename) {

        Resource file = storageService.loadAsResource(filename);
        return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + file.getFilename() + "\"").body(file);
    }

    @PostMapping("/files/upload-xml")
    public String handleXMLFileUpload(@RequestParam("file") MultipartFile file,
                                   RedirectAttributes redirectAttributes) {

        storageService.store(file);
        redirectAttributes.addFlashAttribute("message",
                "You successfully uploaded " + file.getOriginalFilename() + "!");

        return "redirect:/user/upload-xml-file";
    }

    // write doc to output stream
    private static void writeXml(Document doc,
                                 OutputStream output)
            throws TransformerException {

        TransformerFactory transformerFactory = TransformerFactory.newInstance();
        Transformer transformer = transformerFactory.newTransformer();

        DOMSource source = new DOMSource(doc);
        StreamResult result = new StreamResult(output);

        transformer.transform(source, result);

    }

    @PostMapping("/files/xml/update")
    public String handleXMLUpdate(@RequestParam("filename") String fileName,
    		@RequestParam("fcontent") String newXMLContent,
            RedirectAttributes redirectAttributes) {

        Path fpath = storageService.load(fileName);

        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        try {
			dbf.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, false);
	        DocumentBuilder db = dbf.newDocumentBuilder();
	        Document doc = db.parse(new InputSource(new StringReader(newXMLContent)));
	        Path temp = Files.createTempFile("iwa", ".xml");
	        try (FileOutputStream outStream = new FileOutputStream(temp.toString())) {
	        	writeXml(doc, outStream);
	        } catch (IOException | TransformerException e) {
	        	e.printStackTrace();
	        }

	        storageService.store(temp, fpath.toString());
	        Files.delete(temp);
		} catch (ParserConfigurationException | IOException | SAXException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}


        redirectAttributes.addFlashAttribute("message",
                "Successfully updated " + fileName + "!");

        return "redirect:/user/upload-xml-file";
    }

    @ExceptionHandler(StorageFileNotFoundException.class)
    public ResponseEntity<?> handleStorageFileNotFound(StorageFileNotFoundException exc) {
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/download-file")
    public String unverifiedFileAccessIndex(Model model) {
    	model.addAttribute("file", "");
    	return "user/download-file";
    }

    @GetMapping("/files/download/unverified")
    public ResponseEntity<?> serveUnverifiedFile(@Param("file") String file) {

    	if (Objects.isNull(file) || file.isEmpty()) {
    		return ResponseEntity.badRequest().build();
    	}

    	Resource rfile = storageService.loadAsResource(file, true);
        return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + rfile.getFilename() + "\"").body(rfile);
    }

    private String getQRBarcodeURL(String user, String secret) {
        return "otpauth://totp/" + user + "?secret=" + secret;
    }
}
