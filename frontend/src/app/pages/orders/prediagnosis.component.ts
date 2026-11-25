import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { ApiStore } from '../../core/api.store';
import {
  OrderPriority,
  OrderStatus,
  Prediagnosis,
  PrediagnosisResult,
  PrediagnosisValidationStatus,
  ServiceOrder,
} from '../../core/service-order.models';
import { ServiceOrderService } from '../../core/service-order.service';
import { IconComponent } from '../../shared/icon/icon.component';

@Component({
  selector: 'app-prediagnosis',
  standalone: true,
  imports: [DatePipe, FormsModule, IconComponent, RouterLink],
  templateUrl: './prediagnosis.component.html',
})
export class PrediagnosisComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly service = inject(ServiceOrderService);
  private readonly store = inject(ApiStore);
  protected readonly orders = signal<ServiceOrder[]>([]);
  protected readonly history = signal<Prediagnosis[]>([]);
  protected readonly selectedOrderId = signal('');
  protected readonly selectedOrder = computed(() =>
    this.orders().find((order) => order.id === this.selectedOrderId()) ?? null);
  protected readonly activePrediagnosis = signal<Prediagnosis | null>(null);
  protected readonly loading = signal(false);
  protected readonly generating = signal(false);
  protected readonly savingValidation = signal(false);
  protected readonly error = signal('');
  protected readonly feedback = signal('');
  protected additionalSymptoms = '';
  protected observations = '';
  protected editing = false;
  protected discardReason = '';
  protected modifiedResult = this.emptyResult();

  ngOnInit(): void {
    this.route.queryParamMap.subscribe((params) => {
      const orderId = params.get('orderId');
      if (orderId) this.selectedOrderId.set(orderId);
      void this.loadOrders(orderId);
    });
  }

  protected async selectOrder(orderId: string): Promise<void> {
    this.selectedOrderId.set(orderId);
    this.error.set('');
    this.feedback.set('');
    this.additionalSymptoms = '';
    this.observations = this.selectedOrder()?.initialObservations ?? '';
    this.activePrediagnosis.set(null);
    if (orderId) await this.loadHistory(orderId);
    else this.history.set([]);
  }

  protected async generate(): Promise<void> {
    const order = this.selectedOrder();
    if (!order || this.generating()) return;
    this.error.set('');
    this.feedback.set('');
    this.generating.set(true);
    try {
      const result = await this.service.generatePrediagnosis(
        order.id,
        this.additionalSymptoms,
        this.observations,
      );
      this.activePrediagnosis.set(result);
      this.history.update((items) => [result, ...items.filter((item) => item.id !== result.id)]);
      this.editing = false;
      this.feedback.set('Prediagnóstico guardado. Revisa el análisis antes de tomar una decisión técnica.');
    } catch {
      const apiError = this.store.error();
      await this.loadHistory(order.id);
      const fallbackError =
        'Gemini no pudo generar un resultado válido. Tu información sigue disponible; puedes reintentar.';
      this.error.set(apiError || fallbackError);
    } finally {
      this.generating.set(false);
    }
  }

  protected showPrediagnosis(item: Prediagnosis): void {
    this.activePrediagnosis.set(item);
    this.editing = false;
    this.discardReason = '';
    this.modifiedResult = item.result ? structuredClone(item.result) : this.emptyResult();
  }

  protected beginModification(): void {
    const current = this.activePrediagnosis();
    if (!current?.result || current.validationStatus) return;
    this.modifiedResult = structuredClone(current.result);
    this.editing = true;
  }

  protected async accept(): Promise<void> {
    await this.validate('ACEPTADO', '');
  }

  protected async saveModification(): Promise<void> {
    if (!this.activePrediagnosis() || !this.validResult(this.modifiedResult)) {
      this.error.set('Completa la clasificación y al menos una causa, prueba, recomendación y advertencia.');
      return;
    }
    await this.validate('MODIFICADO', '', this.modifiedResult);
    this.editing = false;
  }

  protected async discard(): Promise<void> {
    if (!this.discardReason.trim()) {
      this.error.set('Escribe una observación breve para descartar el prediagnóstico.');
      return;
    }
    await this.validate('DESCARTADO', this.discardReason);
  }

  protected statusLabel(status: PrediagnosisValidationStatus | null): string {
    switch (status ?? 'PENDIENTE') {
      case 'ACEPTADO': return 'Aceptado';
      case 'MODIFICADO': return 'Modificado';
      case 'DESCARTADO': return 'Descartado';
      case 'PENDIENTE': return 'Pendiente de validación';
    }
  }

  protected statusClass(status: PrediagnosisValidationStatus | null): string {
    return `validation-${(status ?? 'PENDIENTE').toLowerCase()}`;
  }

  protected priorityLabel(priority: OrderPriority | PrediagnosisResult['suggestedPriority']): string {
    return priority === 'MEDIA'
      ? 'Media'
      : priority.toLowerCase().replace(/^./, (letter) => letter.toUpperCase());
  }

  protected orderStatusLabel(status: OrderStatus): string {
    return ({
      PENDIENTE: 'Pendiente',
      ASIGNADA: 'Asignada',
      EN_ATENCION: 'En atención',
      FINALIZADA: 'Finalizada',
      CERRADA: 'Cerrada',
      CANCELADA: 'Cancelada',
    })[status];
  }

  protected orderEquipment(order: ServiceOrder): string {
    return `${order.equipmentType} ${order.brand} ${order.model}`.trim();
  }

  protected orderDetailLink(): string[] {
    const ordersPath = this.store.user()?.role === 'TÉCNICO' ? '/mis-ordenes' : '/ordenes';
    return [ordersPath, this.selectedOrderId()];
  }

  protected textToList(value: string): string[] {
    return value.split('\n').map((entry) => entry.trim()).filter(Boolean);
  }

  protected listToText(value: string[]): string {
    return value.join('\n');
  }

  protected async retry(): Promise<void> {
    await this.generate();
  }

  private async loadOrders(preferredId: string | null): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      if (this.store.user()?.role === 'TÉCNICO') {
        await this.service.loadAssigned();
        this.orders.set(this.service.assignedOrders());
      } else {
        await this.service.load();
        this.orders.set(this.service.orders());
      }
      const selected = preferredId && this.orders().some((order) => order.id === preferredId)
        ? preferredId
        : this.orders()[0]?.id ?? '';
      if (selected && selected !== this.selectedOrderId()) this.selectedOrderId.set(selected);
      if (selected) {
        this.observations ||= this.selectedOrder()?.initialObservations ?? '';
        await this.loadHistory(selected);
      }
    } catch {
      this.error.set('No se pudieron cargar órdenes disponibles desde el servidor.');
    } finally {
      this.loading.set(false);
    }
  }

  private async loadHistory(orderId: string): Promise<void> {
    this.loading.set(true);
    try {
      const items = await this.service.getPrediagnoses(orderId);
      this.history.set(items);
      this.activePrediagnosis.set(items[0] ?? null);
      const active = items[0];
      this.modifiedResult = active?.result ? structuredClone(active.result) : this.emptyResult();
    } catch {
      this.history.set([]);
      this.activePrediagnosis.set(null);
      this.error.set('No se pudo consultar el historial de prediagnósticos.');
    } finally {
      this.loading.set(false);
    }
  }

  private async validate(
    decision: 'ACEPTADO' | 'MODIFICADO' | 'DESCARTADO',
    observations: string,
    modifiedResult?: PrediagnosisResult,
  ): Promise<void> {
    const current = this.activePrediagnosis();
    if (!current || this.savingValidation()) return;
    this.savingValidation.set(true);
    this.error.set('');
    this.feedback.set('');
    try {
      await this.service.validatePrediagnosis(current.id, decision, observations, modifiedResult);
      await this.loadHistory(this.selectedOrderId());
      this.feedback.set(`Prediagnóstico ${this.statusLabel(decision)}.`);
      this.discardReason = '';
    } catch {
      this.error.set('No se pudo guardar la validación del prediagnóstico.');
    } finally {
      this.savingValidation.set(false);
    }
  }

  private validResult(result: PrediagnosisResult): boolean {
    return !!result.classification.trim()
      && result.possibleCauses.length > 0 && result.recommendedTests.length > 0
      && result.recommendations.length > 0 && result.warnings.length > 0;
  }

  private emptyResult(): PrediagnosisResult {
    return {
      classification: '',
      suggestedPriority: 'MEDIA',
      possibleCauses: [],
      recommendedTests: [],
      recommendations: [],
      warnings: [],
    };
  }
}
