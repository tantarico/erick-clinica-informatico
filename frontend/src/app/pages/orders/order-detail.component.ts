import { DatePipe, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ApiStore } from '../../core/api.store';
import { PermissionsService } from '../../core/permissions.service';
import {
  EquipmentDelivery,
  OrderPriority,
  OrderStatus,
  Prediagnosis,
  Quotation,
  ServiceOrder,
} from '../../core/service-order.models';
import { ServiceOrderService } from '../../core/service-order.service';
import { IconComponent } from '../../shared/icon/icon.component';

@Component({
  selector: 'app-order-detail',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, IconComponent, RouterLink],
  templateUrl: './order-detail.component.html',
})
export class OrderDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly service = inject(ServiceOrderService);
  private readonly store = inject(ApiStore);
  private readonly permissions = inject(PermissionsService);
  protected readonly order = signal<ServiceOrder | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly feedback = signal('');
  protected readonly quotations = signal<Quotation[]>([]);
  protected readonly delivery = signal<EquipmentDelivery | null>(null);
  protected readonly prediagnoses = signal<Prediagnosis[]>([]);
  protected readonly prediagnosisLoading = signal(false);
  protected readonly prediagnosisError = signal('');
  protected quotationDescription = '';
  protected quotationItemDescription = '';
  protected quotationItemType: 'SERVICIO' | 'REPUESTO' = 'SERVICIO';
  protected quotationQuantity = 1;
  protected quotationUnitPrice = 0;
  protected decisionObservations = '';
  protected deliveryDraft = {
    deliveredAt: '',
    recipientName: '',
    recipientDocument: '',
    receptionSignature: '',
    receptionConstancy: '',
    observations: '',
    clientConfirmed: false,
  };
  protected readonly canAttend = computed(() => {
    const user = this.store.user();
    return !!user && this.permissions.can(user.role, 'attend-orders');
  });
  protected readonly backPath = this.router.url.startsWith('/mis-ordenes') ? '/mis-ordenes' : '/ordenes';

  ngOnInit(): void {
    this.route.paramMap.subscribe((params) => {
      const id = params.get('id');
      if (id) void this.load(id);
    });
  }

  protected async startAttention(): Promise<void> {
    const current = this.order();
    if (!current || (current.status !== 'PENDIENTE' && current.status !== 'ASIGNADA') || this.loading()) return;
    await this.router.navigate(['/atencion', current.id]);
  }

  protected statusLabel(status: OrderStatus): string {
    return ({
      PENDIENTE: 'Pendiente',
      ASIGNADA: 'Asignada',
      EN_ATENCION: 'En atención',
      FINALIZADA: 'Finalizada',
      CERRADA: 'Cerrada',
      CANCELADA: 'Cancelada',
    })[status];
  }

  protected priorityLabel(priority: OrderPriority): string {
    return priority === 'MEDIA'
      ? 'Media'
      : priority.toLowerCase().replace(/^./, (letter) => letter.toUpperCase());
  }

  protected equipmentName(order: ServiceOrder): string {
    return `${order.equipmentType} ${order.brand} ${order.model}`.trim();
  }

  protected canViewPrediagnoses(order: ServiceOrder): boolean {
    const user = this.store.user();
    if (!user || !this.permissions.can(user.role, 'ai-prediagnosis')) return false;
    return user.role === 'TÉCNICO'
      ? order.technicianId === user.id
      : this.permissions.can(user.role, 'attend-orders');
  }

  protected prediagnosisStatusLabel(prediagnosis: Prediagnosis): string {
    if (prediagnosis.status === 'ERROR') return 'Error';
    switch (prediagnosis.validationStatus ?? 'PENDIENTE') {
      case 'ACEPTADO': return 'Aceptado';
      case 'MODIFICADO': return 'Modificado';
      case 'DESCARTADO': return 'Descartado';
      case 'PENDIENTE': return 'Pendiente de validación';
    }
  }

  protected prediagnosisStatusClass(prediagnosis: Prediagnosis): string {
    return prediagnosis.status === 'ERROR'
      ? 'validation-descartado'
      : `validation-${(prediagnosis.validationStatus ?? 'PENDIENTE').toLowerCase()}`;
  }

  protected async createQuotation(): Promise<void> {
    const order = this.order();
    if (!order || !this.quotationDescription.trim()
      || !this.quotationItemDescription.trim()
      || this.quotationQuantity <= 0 || this.quotationUnitPrice < 0) return;
    try {
      await this.service.createQuotation(order.id, {
        description: this.quotationDescription,
        items: [{
          description: this.quotationItemDescription,
          type: this.quotationItemType,
          quantity: this.quotationQuantity,
          unitPrice: this.quotationUnitPrice,
        }],
      });
      this.quotations.set(await this.service.quotations(order.id));
      this.quotationDescription = '';
      this.quotationItemDescription = '';
      this.feedback.set('Cotización registrada.');
    } catch {
      this.error.set('No se pudo registrar la cotización.');
    }
  }

  protected async decideQuotation(
    quotation: Quotation,
    decision: 'AUTORIZADA' | 'RECHAZADA',
  ): Promise<void> {
    try {
      await this.service.decideQuotation(
        quotation.id,
        decision,
        this.decisionObservations,
      );
      const order = this.order();
      if (order) this.quotations.set(await this.service.quotations(order.id));
      this.decisionObservations = '';
      this.feedback.set(`Cotización ${decision.toLowerCase()}.`);
    } catch {
      this.error.set('No se pudo registrar la decisión del cliente.');
    }
  }

  protected async registerDelivery(): Promise<void> {
    const order = this.order();
    if (!order || !this.deliveryDraft.deliveredAt
      || !this.deliveryDraft.recipientName.trim()
      || (!this.deliveryDraft.receptionSignature.trim()
        && !this.deliveryDraft.receptionConstancy.trim())
      || !this.deliveryDraft.clientConfirmed) {
      this.error.set('Completa la fecha, destinatario, confirmación y firma o constancia.');
      return;
    }
    try {
      this.delivery.set(await this.service.deliver(order.id, this.deliveryDraft));
      this.order.set(await this.service.get(order.id));
      this.feedback.set('Entrega registrada y orden cerrada definitivamente.');
    } catch {
      this.error.set('No se pudo registrar la entrega.');
    }
  }

  protected quotationStatusLabel(status: Quotation['status']): string {
    return {
      PENDIENTE: 'Pendiente',
      AUTORIZADA: 'Autorizada',
      RECHAZADA: 'Rechazada',
    }[status];
  }

  protected quotationSubtotal(): number {
    return this.quotationQuantity * this.quotationUnitPrice;
  }

  protected downloadQuotation(quotation: Quotation): void {
    if (quotation.status === 'AUTORIZADA') {
      this.service.downloadQuotationPdf(quotation.id);
    }
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    this.feedback.set('');
    this.prediagnoses.set([]);
    this.prediagnosisLoading.set(false);
    this.prediagnosisError.set('');
    try {
      const [order, quotations, delivery] = await Promise.all([
        this.service.get(id),
        this.service.quotations(id),
        this.service.getDelivery(id),
      ]);
      this.order.set(order);
      this.quotations.set(quotations);
      this.delivery.set(delivery);
      if (this.canViewPrediagnoses(order)) {
        this.prediagnosisLoading.set(true);
        try {
          this.prediagnoses.set(await this.service.getPrediagnoses(id));
        } catch {
          this.prediagnosisError.set('No se pudieron cargar los prediagnósticos de esta orden.');
        } finally {
          this.prediagnosisLoading.set(false);
        }
      } else {
        this.prediagnosisLoading.set(false);
      }
    } catch {
      this.order.set(null);
      this.error.set('No se encontró la orden o no tienes permiso para consultarla.');
    } finally {
      this.loading.set(false);
    }
  }
}
