export type OrderPriority = 'BAJA' | 'MEDIA' | 'ALTA' | 'URGENTE';
export type OrderStatus = 'PENDIENTE' | 'ASIGNADA' | 'EN_ATENCION' | 'FINALIZADA' | 'CERRADA' | 'CANCELADA';

export interface ServiceOrder {
  id: string;
  code: string;
  orderNumber: number;
  receivedDate: string;
  createdAt: string;
  status: OrderStatus;
  priority: OrderPriority;
  reportedProblem: string;
  initialObservations: string;
  clientId: string;
  clientName: string;
  clientDocument: string;
  clientPhone: string;
  equipmentId: string;
  equipmentType: string;
  brand: string;
  model: string;
  serialNumber: string;
  equipmentCharacteristics: string;
  technicianId: string | null;
  technicianName: string | null;
  history?: OrderStatusEntry[];
}

export interface OrderStatusEntry {
  fromStatus: OrderStatus | null;
  toStatus: OrderStatus;
  reason: string;
  changedAt: string;
  changedBy: string;
}

export interface ServiceOrderDraft {
  clientId: string;
  equipmentId: string;
  receivedDate: string;
  reportedProblem: string;
  initialObservations: string;
  priority: OrderPriority;
}

export interface OrderTechnician {
  id: string;
  firstName: string;
  lastName: string;
  username: string;
}

export interface TechnicalAttention {
  id: string;
  orderId: string;
  technicianId: string;
  technicianName: string;
  attendedAt: string;
  diagnosis: string;
  actionsPerformed: string;
  performedTests: string;
  partsUsed: string;
  observations: string;
  resultSummary: string;
  finishedAt: string | null;
}

export interface TechnicalAttentionDraft {
  attendedAt: string;
  diagnosis: string;
  actionsPerformed: string;
  performedTests: string;
  partsUsed: string;
  observations: string;
  resultSummary: string;
}

export interface PrediagnosisResult {
  classification: string;
  suggestedPriority: 'BAJA' | 'MEDIA' | 'ALTA';
  possibleCauses: string[];
  recommendedTests: string[];
  recommendations: string[];
  warnings: string[];
}

export type PrediagnosisValidationStatus =
  | 'ACEPTADO'
  | 'MODIFICADO'
  | 'DESCARTADO'
  | 'PENDIENTE';

export interface Prediagnosis {
  id: string;
  status: 'GENERADO' | 'ERROR';
  model: string;
  originalResponse: string | null;
  result: PrediagnosisResult | null;
  errorMessage: string | null;
  requestedAt: string;
  completedAt: string | null;
  validationStatus: PrediagnosisValidationStatus | null;
  modifiedResult: PrediagnosisResult | null;
  validationObservations: string | null;
  validatedAt: string | null;
  validatedBy: string | null;
}

export interface QuotationItem {
  id: string;
  description: string;
  type: 'SERVICIO' | 'REPUESTO';
  quantity: string;
  unitPrice: string;
  subtotal: string;
}

export interface Quotation {
  id: string;
  orderId: string;
  description: string;
  status: 'PENDIENTE' | 'AUTORIZADA' | 'RECHAZADA';
  total: string;
  createdBy: string;
  decidedBy: string | null;
  decidedAt: string | null;
  decisionObservations: string;
  createdAt: string;
  items: QuotationItem[];
  orderCode?: string;
  clientName?: string;
  equipmentType?: string;
  brand?: string;
  model?: string;
}

export interface QuotationDraft {
  description: string;
  items: Array<{
    description: string;
    type: 'SERVICIO' | 'REPUESTO';
    quantity: number;
    unitPrice: number;
  }>;
}

export interface EquipmentDelivery {
  id: string;
  orderId: string;
  deliveredAt: string;
  responsibleId: string;
  recipientName: string;
  recipientDocument: string;
  receptionSignature: string;
  receptionConstancy: string;
  clientConfirmed: boolean;
  observations: string;
  createdAt: string;
}
