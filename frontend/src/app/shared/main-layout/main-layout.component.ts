import { Component, computed, DestroyRef, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { interval } from 'rxjs';
import { ApiStore } from '../../core/api.store';
import { AuthService, displayUserName } from '../../core/auth.service';
import { displayRoleName, Permission } from '../../core/user.models';
import { PermissionsService } from '../../core/permissions.service';
import { MonitorStatus, SprintSixService } from '../../core/sprint-six.service';
import { IconComponent, IconName } from '../icon/icon.component';

type AlertSeverity = 'error' | 'success';

interface SystemAlert {
  id: string;
  severity: AlertSeverity;
  title: string;
  message: string;
  createdAt: string;
}

interface NavigationItem {
  label: string;
  path: string;
  icon: IconName;
  permission: Permission;
}

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [IconComponent, RouterLink, RouterLinkActive, RouterOutlet],
  templateUrl: './main-layout.component.html',
})
export class MainLayoutComponent {
  protected readonly serverError = inject(ApiStore).error;
  protected readonly menuOpen = signal(false);
  protected readonly notificationsOpen = signal(false);
  protected readonly notifications = signal<SystemAlert[]>([]);
  private readonly authService = inject(AuthService);
  private readonly permissionsService = inject(PermissionsService);
  private readonly monitoringService = inject(SprintSixService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly router = inject(Router);
  protected readonly currentUser = this.authService.currentUser;
  protected readonly isMonitoringAdmin = computed(
    () => this.currentUser()?.role === 'ADMINISTRADOR',
  );
  private readonly activeIncidents = new Set<string>();
  private readonly seenErrorKeys = new Set<string>();
  private monitoring = false;
  private hasInitialErrorSnapshot = false;
  protected readonly profileName = computed(() => {
    const user = this.currentUser();
    return user ? displayUserName(user) : '';
  });
  protected readonly profileRole = computed(() => {
    const role = this.currentUser()?.role;
    return role ? displayRoleName(role) : '';
  });
  protected readonly profileInitials = computed(() => {
    const user = this.currentUser();
    return user ? `${user.firstName.charAt(0)}${user.lastName.charAt(0)}`.toLocaleUpperCase() : '';
  });

  private readonly allPrimaryNavigation: NavigationItem[] = [
    { label: 'Inicio', path: '/dashboard', icon: 'home', permission: 'dashboard' },
    { label: 'Clientes', path: '/clientes', icon: 'users', permission: 'clients' },
    { label: 'Equipos', path: '/equipos', icon: 'laptop', permission: 'equipment' },
    { label: 'Órdenes de Servicio', path: '/ordenes', icon: 'clipboard', permission: 'orders' },
    {
      label: 'Cotizaciones',
      path: '/cotizaciones',
      icon: 'clipboard',
      permission: 'manage-quotations',
    },
    {
      label: 'Mis Órdenes Asignadas',
      path: '/mis-ordenes',
      icon: 'wrench',
      permission: 'assigned-orders',
    },
    {
      label: 'Prediagnóstico con IA',
      path: '/prediagnostico',
      icon: 'sparkles',
      permission: 'ai-prediagnosis',
    },
    {
      label: 'Seguimiento de Servicio',
      path: '/seguimiento',
      icon: 'search',
      permission: 'service-tracking',
    },
    {
      label: 'Indicadores de Servicios',
      path: '/indicadores',
      icon: 'chart',
      permission: 'service-indicators',
    },
    { label: 'Usuarios', path: '/usuarios', icon: 'users', permission: 'users' },
  ];

  protected readonly primaryNavigation = computed(() => {
    const role = this.currentUser()?.role;
    return role
      ? this.allPrimaryNavigation.filter((item) => this.permissionsService.can(role, item.permission))
      : [];
  });

  protected readonly settingsNavigation = computed(() => {
    const role = this.currentUser()?.role;
    return role && this.permissionsService.can(role, 'settings')
      ? [
          { label: 'Auditoría', path: '/auditoria', icon: 'clipboard' as const },
          { label: 'Respaldos', path: '/respaldos', icon: 'shield' as const },
          { label: 'Monitoreo', path: '/monitoreo', icon: 'chart' as const },
          { label: 'Configuración', path: '/configuracion', icon: 'settings' as const },
        ]
      : [];
  });

  protected get hasSettingsNavigation(): boolean {
    return this.settingsNavigation().length > 0;
  }

  constructor() {
    interval(60_000)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => {
        if (this.isMonitoringAdmin()) void this.checkForIncidents();
      });
    if (this.isMonitoringAdmin()) void this.checkForIncidents();
  }

  protected toggleNotifications(): void {
    this.notificationsOpen.update(open => !open);
  }

  protected clearNotifications(): void {
    this.notifications.set([]);
  }

  protected formatAlertTime(value: string): string {
    return new Intl.DateTimeFormat('es', { timeStyle: 'short' }).format(new Date(value));
  }

  protected async signOut(): Promise<void> {
    if (!(await this.authService.signOut())) return;
    void this.router.navigateByUrl('/login');
  }

  protected closeMenu(): void {
    this.menuOpen.set(false);
  }

  private async checkForIncidents(): Promise<void> {
    if (this.monitoring) return;
    this.monitoring = true;
    try {
      const status = await this.monitoringService.monitoring();
      this.trackIncident(
        'backend-unavailable',
        status.backend.status !== 'OK',
        'Backend no disponible',
        status.backend.message,
      );
      this.trackIncident(
        'database-unavailable',
        status.database.status !== 'OK',
        'Base de datos no disponible',
        status.database.message,
      );
      this.trackIncident(
        'ai-unavailable',
        status.ai.configured && status.ai.verified && status.ai.status === 'ERROR',
        'Servicio de IA con errores',
        status.ai.message,
      );
      this.trackRecentErrors(status);
      this.trackIncident(
        'monitoring-backend-unavailable',
        false,
        'Monitoreo restablecido',
        'La consulta de estado volvió a responder.',
      );
    } catch (error) {
      const httpStatus = error instanceof HttpErrorResponse ? error.status : 0;
      const unavailable = httpStatus === 0 || httpStatus >= 500;
      this.trackIncident(
        'monitoring-backend-unavailable',
        unavailable,
        'No se puede consultar el sistema',
        'El backend no respondió. La alerta se actualizará cuando vuelva la conexión.',
      );
    } finally {
      this.monitoring = false;
    }
  }

  private trackRecentErrors(status: MonitorStatus): void {
    const currentKeys = new Set(status.recentErrors.map(error =>
      [error.occurredAt, error.module, error.action, error.message].join('|'),
    ));
    if (this.hasInitialErrorSnapshot) {
      for (const error of status.recentErrors) {
        const key = [error.occurredAt, error.module, error.action, error.message].join('|');
        if (this.seenErrorKeys.has(key)) continue;
        this.addNotification('error', 'Incidencia registrada', `${error.module}: ${error.message}`);
      }
    }
    this.seenErrorKeys.clear();
    for (const key of currentKeys) this.seenErrorKeys.add(key);
    this.hasInitialErrorSnapshot = true;
  }

  private trackIncident(key: string, active: boolean, title: string, message: string): void {
    const wasActive = this.activeIncidents.has(key);
    if (active && !wasActive) {
      this.activeIncidents.add(key);
      this.addNotification('error', title, message);
    } else if (!active && wasActive) {
      this.activeIncidents.delete(key);
      this.addNotification('success', 'Incidencia resuelta', `${title}: el servicio volvió a estar disponible.`);
    }
  }

  private addNotification(severity: AlertSeverity, title: string, message: string): void {
    const alert: SystemAlert = {
      id: `${Date.now()}-${this.notifications().length}`,
      severity,
      title,
      message,
      createdAt: new Date().toISOString(),
    };
    this.notifications.update(alerts => [alert, ...alerts].slice(0, 25));
    if (severity === 'error') this.notificationsOpen.set(true);
  }
}
