export const USER_ROLES = [
  'ADMINISTRADOR',
  'PERSONAL DE ATENCIÓN',
  'TÉCNICO',
  'GERENTE',
] as const;

export type UserRole = (typeof USER_ROLES)[number];

export function displayRoleName(role: UserRole): string {
  switch (role) {
    case 'ADMINISTRADOR':
      return 'Administrador';
    case 'PERSONAL DE ATENCIÓN':
      return 'Personal de Atención';
    case 'TÉCNICO':
      return 'Técnico';
    case 'GERENTE':
      return 'Gerente';
  }
}

export type Permission =
  | 'dashboard'
  | 'clients'
  | 'equipment'
  | 'orders'
  | 'assign-technicians'
  | 'assigned-orders'
  | 'attend-orders'
  | 'ai-prediagnosis'
  | 'service-tracking'
  | 'service-indicators'
  | 'users'
  | 'settings'
  | 'manage-deliveries'
  | 'manage-quotations'
  | 'reports-export';

export interface SystemUser {
  id: string;
  firstName: string;
  lastName: string;
  username: string;
  role: UserRole;
  active: boolean;
}

export interface UserDraft {
  firstName: string;
  lastName: string;
  username: string;
  password: string;
  role: UserRole;
  active: boolean;
}

export type LoginResult = 'success' | 'invalid-credentials' | 'inactive-user' | 'storage-error';

export const PERMISSION_CATALOG: ReadonlyArray<{ id: Permission; label: string }> = [
  { id: 'dashboard', label: 'Ver Dashboard' },
  { id: 'clients', label: 'Gestionar clientes' },
  { id: 'equipment', label: 'Gestionar equipos' },
  { id: 'orders', label: 'Gestionar órdenes' },
  { id: 'assign-technicians', label: 'Asignar técnicos' },
  { id: 'assigned-orders', label: 'Consultar órdenes asignadas' },
  { id: 'attend-orders', label: 'Atender órdenes' },
  { id: 'ai-prediagnosis', label: 'Usar prediagnóstico IA' },
  { id: 'service-tracking', label: 'Consultar seguimiento' },
  { id: 'service-indicators', label: 'Consultar indicadores' },
  { id: 'users', label: 'Gestionar usuarios' },
  { id: 'settings', label: 'Configuración' },
  { id: 'manage-deliveries', label: 'Gestionar entregas' },
  { id: 'manage-quotations', label: 'Gestionar cotizaciones' },
  { id: 'reports-export', label: 'Exportar reportes' },
];
