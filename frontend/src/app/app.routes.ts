import { Routes } from '@angular/router';
import { authGuard, guestGuard, permissionGuard } from './core/auth.guards';
import { LoginComponent } from './pages/login/login.component';
import { OrdersComponent } from './pages/orders/orders.component';
import { MainLayoutComponent } from './shared/main-layout/main-layout.component';

export const routes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: '/login' },
  { path: 'login', component: LoginComponent, canActivate: [guestGuard] },
  {
    path: 'consulta-servicio',
    loadComponent: () => import('./pages/tracking/public-tracking.component')
      .then((module) => module.PublicTrackingComponent),
  },
  {
    path: '',
    component: MainLayoutComponent,
    canActivate: [authGuard],
    canActivateChild: [permissionGuard],
    children: [
      {
        path: 'dashboard',
        loadComponent: () => import('./pages/dashboard/dashboard.component')
          .then(module => module.DashboardComponent),
        data: { permission: 'dashboard' },
      },
      {
        path: 'clientes',
        loadComponent: () => import('./pages/clients/clients.component')
          .then(module => module.ClientsComponent),
        data: { title: 'Clientes', permission: 'clients' },
      },
      {
        path: 'equipos/:id/historial',
        loadComponent: () => import('./pages/equipment-history/equipment-history.component')
          .then((module) => module.EquipmentHistoryComponent),
        data: { permission: 'equipment' },
      },
      {
        path: 'equipos',
        loadComponent: () => import('./pages/equipment/equipment.component')
          .then(module => module.EquipmentComponent),
        data: { title: 'Equipos', permission: 'equipment' },
      },
      {
        path: 'ordenes',
        component: OrdersComponent,
        data: { title: 'Órdenes de Servicio', permission: 'orders' },
      },
      {
        path: 'cotizaciones',
        loadComponent: () => import('./pages/quotations/quotations.component')
          .then(module => module.QuotationsComponent),
        data: { title: 'Cotizaciones', permission: 'manage-quotations' },
      },
      {
        path: 'ordenes/:id',
        loadComponent: () => import('./pages/orders/order-detail.component')
          .then(module => module.OrderDetailComponent),
        data: { permission: 'orders' },
      },
      {
        path: 'mis-ordenes',
        loadComponent: () => import('./pages/orders/assigned-orders.component')
          .then(module => module.AssignedOrdersComponent),
        data: { title: 'Mis Órdenes Asignadas', permission: 'assigned-orders' },
      },
      {
        path: 'mis-ordenes/:id',
        loadComponent: () => import('./pages/orders/order-detail.component')
          .then(module => module.OrderDetailComponent),
        data: { permission: 'assigned-orders' },
      },
      {
        path: 'atencion/:id',
        loadComponent: () => import('./pages/orders/technical-attention.component')
          .then(module => module.TechnicalAttentionComponent),
        data: { permission: 'attend-orders' },
      },
      {
        path: 'prediagnostico',
        loadComponent: () => import('./pages/orders/prediagnosis.component')
          .then(module => module.PrediagnosisComponent),
        data: { title: 'Prediagnóstico con IA', permission: 'ai-prediagnosis' },
      },
      {
        path: 'seguimiento/:id',
        loadComponent: () => import('./pages/tracking/service-tracking.component')
          .then((module) => module.ServiceTrackingComponent),
        data: { permission: 'service-tracking' },
      },
      {
        path: 'seguimiento',
        loadComponent: () => import('./pages/tracking/service-tracking.component')
          .then((module) => module.ServiceTrackingComponent),
        data: { title: 'Seguimiento de Servicio', permission: 'service-tracking' },
      },
      {
        path: 'indicadores',
        loadComponent: () => import('./pages/indicators/indicators.component')
          .then((module) => module.IndicatorsComponent),
        data: { title: 'Indicadores de Servicios', permission: 'service-indicators' },
      },
      {
        path: 'auditoria',
        loadComponent: () => import('./pages/audit/audit.component')
          .then((module) => module.AuditComponent),
        data: { title: 'Auditoría', permission: 'settings' },
      },
      {
        path: 'respaldos',
        loadComponent: () => import('./pages/backups/backups.component')
          .then((module) => module.BackupsComponent),
        data: { title: 'Respaldos', permission: 'settings' },
      },
      {
        path: 'monitoreo',
        loadComponent: () => import('./pages/monitoring/monitoring.component')
          .then((module) => module.MonitoringComponent),
        data: { title: 'Monitoreo', permission: 'settings' },
      },
      {
        path: 'usuarios',
        loadComponent: () => import('./pages/users/users.component')
          .then(module => module.UsersComponent),
        data: { permission: 'users' },
      },
      {
        path: 'configuracion',
        loadComponent: () => import('./pages/settings/settings.component')
          .then((module) => module.SettingsComponent),
        data: { title: 'Configuración', permission: 'settings' },
      },
    ],
  },
  { path: '**', redirectTo: 'login' },
];
