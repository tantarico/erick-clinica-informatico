import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { inject, Injectable, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { Client } from './client.models';
import { Equipment } from './equipment.models';
import { Permission, SystemUser, UserRole } from './user.models';
const API_BASE_URL = 'https://TU-BACKEND.up.railway.app/api';

export interface TechnicianOrder {
  id: string;
  orderNumber: number;
  priority: 'BAJA' | 'NORMAL' | 'ALTA' | 'URGENTE';
  status: string;
  reportedProblem: string;
  equipmentType: string;
  brand: string;
  model: string;
  serialNumber: string;
  clientName: string;
}

export interface BootstrapData {
  user: SystemUser;
  users: SystemUser[];
  clients: Client[];
  equipment: Equipment[];
  technicianOrders: TechnicianOrder[];
  permissions: Record<UserRole, Permission[]>;
}

@Injectable({ providedIn: 'root' })
export class ApiStore {
  readonly http = inject(HttpClient);
  readonly user = signal<SystemUser | null>(null);
  readonly users = signal<SystemUser[]>([]);
  readonly clients = signal<Client[]>([]);
  readonly equipment = signal<Equipment[]>([]);
  readonly technicianOrders = signal<TechnicianOrder[]>([]);
  readonly permissions = signal<Record<UserRole, Permission[]>>({
    ADMINISTRADOR: [], 'PERSONAL DE ATENCIÓN': [], TÉCNICO: [], GERENTE: [],
  });
  readonly error = signal('');
  readonly pending = signal(0);

  async initialize(): Promise<void> {
    try { await this.refresh(); }
    catch (error) {
      this.clear();
      if (!(error instanceof HttpErrorResponse && error.status === 401))
        this.error.set('No se pudo conectar con el servidor. Comprueba que el backend y PostgreSQL están en ejecución.');
    }
  }

  async refresh(): Promise<void> {
    const data = await firstValueFrom(this.http.get<BootstrapData>('/api/bootstrap'));
    this.user.set(data.user);
    this.users.set(data.users);
    this.clients.set(data.clients);
    this.equipment.set(data.equipment);
    this.technicianOrders.set(data.technicianOrders);
    this.permissions.set(data.permissions);
    this.error.set('');
  }

  clear(): void {
    this.user.set(null); this.users.set([]); this.clients.set([]); this.equipment.set([]);
    this.technicianOrders.set([]);
    this.permissions.set({ ADMINISTRADOR: [], 'PERSONAL DE ATENCIÓN': [], TÉCNICO: [], GERENTE: [] });
  }

  async write<T>(method: string, path: string, body?: unknown): Promise<T> {
    this.pending.update(value => value + 1);
    this.error.set('');
    try {
      return await firstValueFrom(this.http.request<T>(method, '/api' + path, { body }));
    } catch (error) {
      const code = apiErrorCode(error);
      if (error instanceof HttpErrorResponse && error.status === 401 && path !== '/auth/login') {
        this.clear();
        this.error.set('Tu sesión terminó. Vuelve a iniciar sesión.');
      } else {
        const messages: Record<string, string> = {
          'invalid-data': 'Revisa los datos. Las contraseñas nuevas requieren entre 10 caracteres y 72 bytes.',
          'related-records': 'El registro tiene información relacionada y no se puede eliminar.',
          'self-change': 'No puedes desactivar tu usuario ni cambiar tu propio rol.',
          'last-admin': 'Debe existir al menos un administrador activo.',
          'equipment-client-mismatch': 'El equipo seleccionado no pertenece al cliente indicado.',
          'invalid-technician': 'Solo puedes asignar usuarios activos con rol TÉCNICO.',
          'technician-required': 'Asigna un técnico antes de iniciar la atención.',
          'diagnostic-required': 'La orden necesita diagnóstico y resultado técnico antes de finalizar.',
          'invalid-transition': 'Ese cambio de estado no está permitido.',
          'status-unchanged': 'La orden ya tiene ese estado.',
          'order-closed': 'No se pueden asignar técnicos a una orden finalizada.',
          'duplicate-order-code': 'El código de la orden ya existe. Vuelve a intentarlo.',
          'order-finalized': 'La orden finalizada es de solo consulta.',
          'attention-incomplete': 'Completa diagnóstico, actividades y resultado antes de finalizar.',
          'attention-not-started': 'Inicia la atención técnica antes de finalizar.',
          'finalization-required': 'Finaliza la orden desde el módulo de atención técnica.',
          'ai-not-configured': 'El prediagnóstico no está configurado en el servidor.',
          'ai-generation-failed': 'Gemini no generó una respuesta válida. Puedes reintentar.',
          'ai-already-validated': 'El prediagnóstico ya fue revisado.',
          'ai-result-unavailable': 'No se puede validar un análisis que no se generó correctamente.',
          'discard-reason-required': 'Escribe el motivo para descartar el prediagnóstico.',
          forbidden: 'No tienes permiso para realizar esta acción.',
          'protected-permission': 'Este permiso está reservado o es obligatorio.',
        };
        this.error.set(messages[code] ?? 'No se pudo completar la operación. Comprueba la conexión con el servidor.');
      }
      throw error;
    } finally { this.pending.update(value => value - 1); }
  }
}

export function apiErrorCode(error: unknown): string {
  return error instanceof HttpErrorResponse && typeof error.error?.code === 'string'
    ? error.error.code : 'server-error';
}
