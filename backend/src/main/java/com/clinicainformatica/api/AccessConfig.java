package com.clinicainformatica.api;

import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DataAccessException;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
@Configuration
public class AccessConfig implements WebMvcConfigurer, HandlerInterceptor {
    private static final System.Logger LOGGER = System.getLogger(AccessConfig.class.getName());
    private static final String REQUEST_GATE_ATTRIBUTE = AccessConfig.class.getName() + ".requestGate";
    private final ClinicRepository repository;
    private final BackupMaintenanceGate maintenanceGate;
    public AccessConfig(ClinicRepository repository, BackupMaintenanceGate maintenanceGate) {
        this.repository = repository;
        this.maintenanceGate = maintenanceGate;
    }
    @Override public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**").excludePathPatterns("/api/health");
    }
    @Override public boolean preHandle(HttpServletRequest request,HttpServletResponse response,Object handler) {
        response.setHeader("Cache-Control","no-store");
        String path = (String) request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
        boolean restoreRequest = request.getMethod().equals("POST")
            && "/api/admin/backups/{id}/restore".equals(path);
        if (restoreRequest && maintenanceGate.isRestorationRequested()) {
            throw new ApiException(HttpStatus.CONFLICT, "restore-in-progress",
                "Ya hay una restauración en ejecución.");
        }
        if (!restoreRequest) {
            if (!maintenanceGate.tryEnterRequest()) {
                throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "system-restoring",
                    "El sistema está en mantenimiento por una restauración. Inténtalo más tarde.");
            }
            request.setAttribute(REQUEST_GATE_ATTRIBUTE, Boolean.TRUE);
        }
        try {
            return authorize(request, response, path);
        } catch (RuntimeException e) {
            releaseRequestGate(request);
            throw e;
        }
    }

    private boolean authorize(HttpServletRequest request, HttpServletResponse response, String path) {
        // All requests use the same-origin Angular proxy; no CORS is enabled.
        // A custom header on mutations blocks cross-origin form submissions (CSRF).
        if (!request.getMethod().equals("GET") && !"XMLHttpRequest".equals(request.getHeader("X-Requested-With")))
            throw new ApiException(HttpStatus.FORBIDDEN,"csrf","Solicitud no válida.");
        if("/api/auth/login".equals(path)) return true;
        if("/api/public/tracking".equals(path)) return true;
        var session=request.getSession(false);
        var id=session == null ? null : (UUID) session.getAttribute("userId");
        if (id == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED,"unauthorized","Inicia sesión para continuar.");
        }
        Map<String,Object> user;
        try {
            user=repository.user(id);
        } catch (DataAccessException e) {
            if ("/api/admin/monitoring".equals(path)
                && "ADMINISTRADOR".equals(session.getAttribute("userRole"))) {
                request.setAttribute("currentUser",Map.of("id",id.toString(),"role","ADMINISTRADOR"));
                return true;
            }
            throw e;
        }
        if(user == null || !Boolean.TRUE.equals(user.get("active"))) {
            if(session != null) session.invalidate();
            throw new ApiException(HttpStatus.UNAUTHORIZED,"unauthorized","Inicia sesión para continuar.");
        }
        request.setAttribute("currentUser",user);
        String role = (String) user.get("role");
        if ("/api/admin/monitoring".equals(path)) {
            if (!"ADMINISTRADOR".equals(role)) {
                throw new ApiException(HttpStatus.FORBIDDEN,"forbidden","No tienes permiso para realizar esta acción.");
            }
            return true;
        }
        String permission = permissionFor(path, request.getMethod(), role);
        boolean orderRead = request.getMethod().equals("GET")
            && ("/api/orders".equals(path) || "/api/orders/{id}".equals(path));
        boolean orderStatusChange = "/api/orders/{id}/status".equals(path);
        boolean allowed = orderRead
            ? repository.can(role,"orders") || repository.can(role,"assigned-orders")
            : orderStatusChange
                ? repository.can(role,"orders") || repository.can(role,"attend-orders")
            : path != null && (path.equals("/api/orders/{id}/attention")
                || path.equals("/api/orders/{id}/finalize"))
                ? repository.can(role,"attend-orders")
            : path != null && (path.equals("/api/orders/{id}/prediagnoses")
                || path.equals("/api/prediagnoses/{id}/validation"))
                ? repository.can(role,"ai-prediagnosis")
            : permission == null || repository.can(role,permission);
        if(!allowed)
            throw new ApiException(HttpStatus.FORBIDDEN,"forbidden","No tienes permiso para realizar esta acción.");
        return true;
    }

    @Override public void afterCompletion(HttpServletRequest request,HttpServletResponse response,
        Object handler,Exception exception) {
        try {
            if (response.getStatus() < HttpServletResponse.SC_BAD_REQUEST
                || request.getMethod().equals("GET")) return;
            Object currentUser=request.getAttribute("currentUser");
            if(!(currentUser instanceof java.util.Map<?,?> actor)) return;
            UUID actorId=UUID.fromString((String)actor.get("id"));
            String path=(String)request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
            String entity=path == null ? "api" : path.replaceFirst("^/api/","");
            try {
                repository.audit(actorId,"REQUEST_FAILED",entity,null,"FAILED",
                    "La solicitud " + request.getMethod() + " " + (path == null ? "/api" : path)
                        + " terminó con HTTP " + response.getStatus() + ".");
            } catch (DataAccessException e) {
                LOGGER.log(System.Logger.Level.ERROR, "No se pudo registrar en auditoría una solicitud fallida.", e);
            }
        } finally {
            releaseRequestGate(request);
        }
    }

    private void releaseRequestGate(HttpServletRequest request) {
        if (Boolean.TRUE.equals(request.getAttribute(REQUEST_GATE_ATTRIBUTE))) {
            request.removeAttribute(REQUEST_GATE_ATTRIBUTE);
            maintenanceGate.leaveRequest();
        }
    }

    private String permissionFor(String path,String method,String role) {
        if(path == null) return null;
        if(path.startsWith("/api/admin/")) return "settings";
        if(path.startsWith("/api/indicators/")) return "service-indicators";
        if(path.startsWith("/api/reports/")) return "reports-export";
        if(path.contains("/quotation")) return "manage-quotations";
        if(path.contains("/delivery")) return "manage-deliveries";
        if(path.startsWith("/api/users") || path.startsWith("/api/permissions")) return "users";
        if(path.startsWith("/api/clients")) return "clients";
        if(path.startsWith("/api/equipment")) return "equipment";
        if(path.startsWith("/api/tracking")) return "service-tracking";
        if(path.startsWith("/api/quotations")) return "manage-quotations";
        if(path.equals("/api/orders/mine")) return "assigned-orders";
        if(path.equals("/api/orders/technicians") || path.equals("/api/orders/{id}/assignment"))
            return "assign-technicians";
        if(path.equals("/api/orders/{id}/status"))
            return "TÉCNICO".equals(role) ? "attend-orders" : "orders";
        if(path.equals("/api/orders/{id}/attention") || path.equals("/api/orders/{id}/finalize"))
            return "attend-orders";
        if(path.equals("/api/orders/{id}/prediagnoses")
            || path.equals("/api/prediagnoses/{id}/validation"))
            return "ai-prediagnosis";
        if(path.startsWith("/api/orders")) {
            if(method.equals("GET")) return "orders";
            return "orders";
        }
        return null;
    }
}
